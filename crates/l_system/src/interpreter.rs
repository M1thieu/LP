use glam::{Vec2, Quat};
use std::collections::HashSet;

/// Represents the output of the interpreter: positions and directions for rendering
pub struct InterpreterOutput {
    pub positions: Vec<(Vec2, Vec2)>, // List of line segments (start, end)
}

/// Interprets L-System symbols and computes positions and directions
pub fn interpret(
    symbols: &str,
    rotation_angle: f32,
    line_length: f32,
    scale_factor: f32, // Added scale factor parameter
    angle_variation: f32, // Added angle variation parameter
) -> Result<InterpreterOutput, String> {
    let valid_symbols = HashSet::from(['F', '+', '-', '[', ']']);
    if symbols.chars().any(|ch| !valid_symbols.contains(&ch)) {
        return Err("Invalid symbol in L-System string".to_string());
    }

    let mut stack: Vec<(Vec2, Vec2, f32)> = Vec::new(); // Stack now stores position, direction, and current scale
    let mut position = Vec2::ZERO;
    let mut direction = Vec2::Y;
    let mut output = InterpreterOutput { positions: Vec::new() };

    let mut current_scale = 1.0; // Track consistent scaling per iteration
    let mut bracket_depth = 0; // Track current bracket nesting depth

    for ch in symbols.chars() {
        match ch {
            'F' => {
                // Scale based on bracket depth
                let depth_scale = scale_factor.powf(bracket_depth as f32);
                let scaled_length = line_length * current_scale * depth_scale;
                
                let new_position = position + direction * scaled_length;
                output.positions.push((position, new_position));
                position = new_position;
            }
            '+' => {
                // Apply rotation with angle variation based on bracket depth
                // We'll pass the variation value from the renderer instead of generating it here
                let variation_factor = angle_variation * bracket_depth as f32;
                let varied_angle = rotation_angle * (1.0 + variation_factor);
                
                direction = Quat::from_rotation_z(-varied_angle.to_radians())
                    .mul_vec3(direction.extend(0.0))
                    .truncate();
            }
            '-' => {
                // Apply rotation with angle variation based on bracket depth
                // We'll pass the variation value from the renderer instead of generating it here
                let variation_factor = angle_variation * bracket_depth as f32; 
                let varied_angle = rotation_angle * (1.0 + variation_factor);
                
                direction = Quat::from_rotation_z(varied_angle.to_radians())
                    .mul_vec3(direction.extend(0.0))
                    .truncate();
            }
            '[' => {
                stack.push((position, direction, current_scale)); // Save scale state too
                bracket_depth += 1; // Increase depth when entering a branch
            }
            ']' => {
                if let Some((saved_position, saved_direction, saved_scale)) = stack.pop() {
                    position = saved_position;
                    direction = saved_direction;
                    current_scale = saved_scale; // Restore previous scale
                    bracket_depth -= 1; // Decrease depth when leaving a branch
                }
            }
            _ => {}
        }
    }

    Ok(output)
}