use image::DynamicImage;
use imageproc::contrast::adaptive_threshold;
use rscam::{Camera, Config};
use serde::{Deserialize, Serialize};
use std::fs;
use std::process;
use std::io::{self, Write};
use std::time::Duration;

const FACE_SIZE: u32 = 64;
const FRAMES_PER_CAPTURE: usize = 15;
const ENROLLMENT_CAPTURES: usize = 3;

#[derive(Serialize, Deserialize, Debug)]
struct FaceProfile {
    username: String,
    face_templates: Vec<Vec<u8>>,
    created_at: String,
}

fn log_pam(message: &str) {
    if std::env::var("PAM_USER").is_ok() || std::env::var("DEBUG_AUTH").is_ok() {
        let log_paths = ["/var/log/sayhi.log", "/tmp/sayhi.log"];
        for path in &log_paths {
            if let Ok(mut f) = fs::OpenOptions::new().create(true).append(true).open(path) {
                let _ = writeln!(f, "[{}] {}", get_timestamp(), message);
                break;
            }
        }
    }
}

fn get_dataset_dir() -> String {
    // Determina usuário atual
    let username = std::env::var("PAM_USER")
        .or_else(|_| std::env::var("USER"))
        .unwrap_or_else(|_| "unknown".to_string());

    if username == "root" || username == "unknown" {
        return "/var/lib/sayhilinux".to_string();
    }

    if let Ok(home) = std::env::var("HOME") {
        return format!("{}/.local/share/sayhilinux", home);
    }

    let home_path = format!("/home/{}", username);
    if std::path::Path::new(&home_path).exists() {
        format!("{}/.local/share/sayhilinux", home_path)
    } else {
        format!("/var/lib/sayhilinux/{}", username)
    }
}

fn main() {
    let args: Vec<String> = std::env::args().collect();

    if args.len() < 2 {
        eprintln!("Usage:");
        eprintln!("  sayhi enroll <username>  - Enroll user face");
        eprintln!("  sayhi auth [username]    - Authenticate user");
        eprintln!("  sayhi test               - Test camera");
        process::exit(1);
    }

    match args[1].as_str() {
        "enroll" => {
            if args.len() < 3 {
                eprintln!("Error: Username required");
                process::exit(1);
            }
            enroll_user(&args[2]);
        }
        "auth" => {
            let username = args.get(2).map(|s| s.as_str());
            authenticate(username);
        }
        "test" => {
            test_camera();
        }
        _ => {
            eprintln!("Invalid command: {}", args[1]);
            process::exit(1);
        }
    }
}

fn test_camera() {
    println!("Testing camera...");
    match capture_frame() {
        Ok(img) => {
            let path = "/tmp/sayhi_test.jpg";
            img.save(path).expect("Failed to save image");
            let quality = analyze_image_quality(&img);
            println!("Camera OK");
            println!("Image saved to: {}", path);
            println!("Brightness: {:.1}%", quality.brightness * 100.0);
            println!("Contrast: {:.1}%", quality.contrast * 100.0);
            process::exit(0);
        }
        Err(e) => {
            eprintln!("Camera error: {}", e);
            process::exit(1);
        }
    }
}

fn enroll_user(username: &str) {
    println!("Face Enrollment for user: {}", username);
    println!("Ensure good lighting and look at the camera.");

    let dataset_dir = get_dataset_dir();
    fs::create_dir_all(&dataset_dir).unwrap_or_else(|e| {
        eprintln!("Error creating directory {}: {}", dataset_dir, e);
        process::exit(1);
    });

    let mut all_templates = Vec::new();

    for capture_num in 1..=ENROLLMENT_CAPTURES {
        println!("\nCapture {}/{}", capture_num, ENROLLMENT_CAPTURES);
        println!("Press Enter to start...");
        let mut input = String::new();
        io::stdin().read_line(&mut input).unwrap();
        print!("Capturing... ");
        io::stdout().flush().unwrap();

        match capture_video_frames() {
            Ok(templates) => {
                println!("OK ({} frames)", templates.len());
                all_templates.extend(templates);
            }
            Err(e) => {
                println!("FAILED: {}", e);
                println!("Please try again.");
                continue;
            }
        }
        std::thread::sleep(Duration::from_millis(500));
    }

    if all_templates.len() < 10 {
        eprintln!("Error: Insufficient frames captured (minimum 10 required).");
        process::exit(1);
    }

    let profile = FaceProfile {
        username: username.to_string(),
        face_templates: all_templates,
        created_at: get_timestamp(),
    };

    let profile_path = format!("{}/{}.json", dataset_dir, username);
    let json = serde_json::to_string_pretty(&profile).unwrap();

    fs::write(&profile_path, json).unwrap_or_else(|e| {
        eprintln!("Error saving profile: {}", e);
        process::exit(1);
    });

    println!("Enrollment completed. Profile saved to: {}", profile_path);
    process::exit(0);
}

fn authenticate(username_arg: Option<&str>) {
    let is_pam = std::env::var("PAM_USER").is_ok();
    let username = username_arg
        .map(|s| s.to_string())
        .or_else(|| std::env::var("PAM_USER").ok())
        .or_else(|| std::env::var("USER").ok())
        .unwrap_or_else(|| "unknown".to_string());

    log_pam(&format!("Authentication started: {}", username));

    let attempts_file = format!("/tmp/sayhi-attempts-{}", username);
    let max_attempts = 3;
    let mut current_attempts = 0;

    if let Ok(content) = fs::read_to_string(&attempts_file) {
        current_attempts = content.trim().parse().unwrap_or(0);
    }

    if current_attempts >= max_attempts {
        log_pam("Blocked: Maximum attempts reached");
        let _ = fs::remove_file(&attempts_file);
        process::exit(1);
    }

    let profile = match load_user_profile(&username) {
        Some(p) => p,
        None => {
            log_pam("Profile not found");
            process::exit(1);
        }
    };

    if !is_pam {
        println!("Authenticating {}...", username);
    }

    match capture_video_frames() {
        Ok(current_templates) => {
            let similarity = compare_templates_batch(&current_templates, &profile.face_templates);

            if similarity >= 0.65 {
                let _ = fs::remove_file(&attempts_file);
                log_pam(&format!("Success: {:.1}%", similarity * 100.0));

                if !is_pam {
                    println!("SUCCESS! Confidence: {:.1}%", similarity * 100.0);
                }
                process::exit(0);
            } else {
                current_attempts += 1;
                let _ = fs::write(&attempts_file, current_attempts.to_string());
                log_pam(&format!("Failed: {:.1}%", similarity * 100.0));

                if !is_pam {
                    println!("FAILED. Confidence: {:.1}%", similarity * 100.0);
                }
                process::exit(1);
            }
        }
        Err(e) => {
            log_pam(&format!("Capture error: {}", e));
            process::exit(1);
        }
    }
}

// ======= Camera capture & processing =======

fn capture_frame() -> Result<DynamicImage, String> {
    let camera = setup_camera()?;
    for _ in 0..5 {
        let _ = camera.capture();
        std::thread::sleep(Duration::from_millis(50));
    }
    let frame = camera.capture().map_err(|e| e.to_string())?;
    let img = image::load_from_memory(&frame[..]).map_err(|e| e.to_string())?;
    Ok(img)
}

fn capture_video_frames() -> Result<Vec<Vec<u8>>, String> {
    let camera = setup_camera()?;
    for _ in 0..5 {
        let _ = camera.capture();
        std::thread::sleep(Duration::from_millis(50));
    }
    let mut templates = Vec::new();
    for _ in 0..FRAMES_PER_CAPTURE {
        if let Ok(frame) = camera.capture() {
            if let Ok(img) = image::load_from_memory(&frame[..]) {
                if let Ok(template) = process_face_image(&img) {
                    templates.push(template);
                }
            }
        }
        std::thread::sleep(Duration::from_millis(33));
    }
    if templates.is_empty() {
        return Err("No processable faces captured".to_string());
    }
    Ok(templates)
}

fn setup_camera() -> Result<Camera, String> {
    let device = if std::path::Path::new("/dev/video0").exists() { "/dev/video0" }
                 else if std::path::Path::new("/dev/video1").exists() { "/dev/video1" }
                 else { return Err("Camera not found (/dev/video0 or /dev/video1)".to_string()); };
    let mut camera = Camera::new(device).map_err(|e| e.to_string())?;
    camera.start(&Config {
        interval: (1, 30),
        resolution: (640, 480),
        format: b"MJPG",
        ..Default::default()
    }).map_err(|e| format!("Camera configuration error (try changing MJPG to YUYV): {}", e))?;
    Ok(camera)
}

fn process_face_image(img: &DynamicImage) -> Result<Vec<u8>, String> {
    let gray = img.to_luma8();
    let resized = image::imageops::resize(&gray, FACE_SIZE, FACE_SIZE, image::imageops::FilterType::Triangle);
    let normalized = adaptive_threshold(&resized, 15);
    Ok(normalized.into_raw())
}

// ======= Helpers =======

struct ImageQuality {
    brightness: f32,
    contrast: f32,
}

fn analyze_image_quality(img: &DynamicImage) -> ImageQuality {
    let gray = img.to_luma8();
    let pixels = gray.as_raw();
    let sum: u64 = pixels.iter().map(|&p| p as u64).sum();
    let count = pixels.len() as f32;
    let brightness = (sum as f32) / (count * 255.0);
    let mean = sum as f32 / count;
    let variance: f32 = pixels.iter().map(|&p| {
        let diff = p as f32 - mean;
        diff * diff
    }).sum::<f32>() / count;
    let contrast = variance.sqrt() / 128.0;
    ImageQuality { brightness, contrast }
}

fn compare_templates_batch(batch1: &[Vec<u8>], batch2: &[Vec<u8>]) -> f32 {
    let mut total_score = 0.0;
    let mut count = 0;
    let step1 = (batch1.len() / 5).max(1);
    let step2 = (batch2.len() / 10).max(1);
    for t1 in batch1.iter().step_by(step1) {
        let mut best_match = 0.0;
        for t2 in batch2.iter().step_by(step2) {
            let score = compare_templates(t1, t2);
            if score > best_match { best_match = score; }
        }
        total_score += best_match;
        count += 1;
    }
    if count == 0 { 0.0 } else { total_score / count as f32 }
}

fn compare_templates(t1: &[u8], t2: &[u8]) -> f32 {
    if t1.len() != t2.len() { return 0.0; }
    let n = t1.len() as f32;
    let mut sum1 = 0.0;
    let mut sum2 = 0.0;
    let mut sum1_sq = 0.0;
    let mut sum2_sq = 0.0;
    let mut p_sum = 0.0;
    for i in 0..t1.len() {
        let x = t1[i] as f32;
        let y = t2[i] as f32;
        sum1 += x;
        sum2 += y;
        sum1_sq += x * x;
        sum2_sq += y * y;
        p_sum += x * y;
    }
    let num = p_sum - (sum1 * sum2 / n);
    let den = ((sum1_sq - (sum1 * sum1 / n)) * (sum2_sq - (sum2 * sum2 / n))).sqrt();
    if den == 0.0 { return 0.0; }
    ((num / den) + 1.0) / 2.0
}

fn load_user_profile(username: &str) -> Option<FaceProfile> {
    let path = format!("{}/{}.json", get_dataset_dir(), username);
    if let Ok(content) = fs::read_to_string(&path) {
        return serde_json::from_str(&content).ok();
    }
    None
}

fn get_timestamp() -> String {
    format!("{}", std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs())
}

