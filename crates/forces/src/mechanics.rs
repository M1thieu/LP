use bevy::prelude::*;

/// Trait for computing the squared norm of a vector efficiently
pub trait Norm {
    type Output;
    fn norm_squared(self) -> Self::Output;
}

/// Trait for computing the squared distance between vectors
pub trait Distance: Norm + std::ops::Sub<Output = Self> + Sized {
    fn distance_squared(self, other: Self) -> <Self as Norm>::Output {
        (self - other).norm_squared()
    }
}

// Implement for Vec3
impl Norm for Vec3 {
    type Output = f32;
    #[inline]
    fn norm_squared(self) -> f32 {
        self.length_squared()
    }
}

impl Distance for Vec3 {}

// Implement for Vec2
impl Norm for Vec2 {
    type Output = f32;
    #[inline]
    fn norm_squared(self) -> f32 {
        self.length_squared() 
    }
}

impl Distance for Vec2 {}

/// Component for mass properties of an entity
#[derive(Component, Debug, Clone, Copy)]
pub struct Mass {
    /// Mass in kilograms
    pub value: f32,
    /// Whether this object has infinite mass (immovable)
    pub is_infinite: bool,
}

impl Mass {
    pub fn new(value: f32) -> Self {
        Self {
            value: value.max(0.001), // Prevent zero or negative mass
            is_infinite: false,
        }
    }

    pub fn infinite() -> Self {
        Self {
            value: f32::MAX,
            is_infinite: true,
        }
    }
    
    pub fn inverse(&self) -> f32 {
        if self.is_infinite {
            0.0
        } else {
            1.0 / self.value.max(f32::EPSILON)
        }
    }
    
    /// Returns true if this mass is effectively zero
    pub fn is_negligible(&self) -> bool {
        self.value < 0.001
    }
    
    /// Safely compute the reduced mass of two objects (for two-body systems)
    pub fn reduced_mass(&self, other: &Mass) -> f32 {
        if self.is_infinite || other.is_infinite {
            return self.value.min(other.value);
        }
        
        let sum = self.value + other.value;
        if sum < f32::EPSILON {
            return 0.0;
        }
        
        (self.value * other.value) / sum
    }
}

/// Component representing a force applied to an entity
#[derive(Component, Debug, Clone)]
pub struct AppliedForce {
    /// Force vector in Newtons
    pub force: Vec3,
    /// Application point relative to entity center
    pub application_point: Option<Vec3>,
    /// Duration the force is applied (None for continuous)
    pub duration: Option<f32>,
    /// Elapsed time since force began
    pub elapsed: f32,
}

impl AppliedForce {
    pub fn new(force: Vec3) -> Self {
        Self {
            force,
            application_point: None,
            duration: None,
            elapsed: 0.0,
        }
    }
    
    pub fn with_application_point(mut self, point: Vec3) -> Self {
        self.application_point = Some(point);
        self
    }
    
    pub fn with_duration(mut self, duration: f32) -> Self {
        self.duration = Some(duration);
        self
    }
    
    pub fn is_expired(&self) -> bool {
        if let Some(duration) = self.duration {
            self.elapsed >= duration
        } else {
            false
        }
    }
}

/// System to apply forces according to Newton's Second Law (F = ma)
pub fn apply_forces(
    time: Res<Time>,
    mut query: Query<(&Mass, &mut Velocity, &mut AppliedForce)>,
) {
    let dt = time.delta_secs();
    
    for (mass, mut velocity, mut force) in query.iter_mut() {
        // Skip infinite mass objects and effectively massless objects
        if mass.is_infinite || mass.is_negligible() {
            continue;
        }
        
        // Calculate acceleration using F = ma with safety against division by zero
        let acceleration = force.force * mass.inverse();
        
        // Cap extremely high accelerations to prevent instability
        let max_acceleration = 1000.0; // Arbitrary limit to prevent numerical issues
        let acceleration = if acceleration.norm_squared() > max_acceleration * max_acceleration {
            acceleration.normalize() * max_acceleration
        } else {
            acceleration
        };
        
        // Update velocity using acceleration
        velocity.linvel += acceleration * dt;
        
        // Update force duration
        force.elapsed += dt;
    }
}

/// System to apply Verlet integration for position updates
pub fn integrate_positions(
    time: Res<Time>,
    mut query: Query<(&Velocity, &mut Transform)>,
) {
    let dt = time.delta_secs();
    
    for (velocity, mut transform) in query.iter_mut() {
        // Update position using velocity
        transform.translation += velocity.linvel * dt;
        
        // Apply angular velocity
        if velocity.angvel.norm_squared() > 0.0 {
            transform.rotation *= Quat::from_scaled_axis(velocity.angvel * dt);
        }
    }
}

/// Component for velocity (both linear and angular)
#[derive(Component, Debug, Clone, Copy)]
pub struct Velocity {
    /// Linear velocity in meters per second
    pub linvel: Vec3,
    /// Angular velocity in radians per second
    pub angvel: Vec3,
}

impl Default for Velocity {
    fn default() -> Self {
        Self {
            linvel: Vec3::ZERO,
            angvel: Vec3::ZERO,
        }
    }
}

/// Calculate momentum of an object
pub fn calculate_momentum(mass: &Mass, velocity: &Velocity) -> Vec3 {
    mass.value * velocity.linvel
}

/// Calculate kinetic energy of an object
pub fn calculate_kinetic_energy(mass: &Mass, velocity: &Velocity) -> f32 {
    0.5 * mass.value * velocity.linvel.norm_squared()
}