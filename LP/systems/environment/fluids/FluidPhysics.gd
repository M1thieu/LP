extends Node2D

var fluid_instance: MultiMeshInstance2D
var multimesh := MultiMesh.new()

@export var particle_count := 200
@export var boundary_size := 250
@export var particle_size := 6.0
@export var interaction_radius := 25.00
@export var rest_density := 1.5
@export var stiffness := 200.0  # Pressure stiffness
@export var viscosity := 0.1   # Viscosity factor
@export var velocity_damping := 0.97  # Velocity reduction upon collision
@export var mouse_interaction_radius := 100.0  # Radius for particle interaction with mouse
@export var particle_mass := 1.0  # Mass per particle
@export var gravity: Vector2 = Vector2(0, 9.8)  # Gravity in the downward direction
@export var surface_tension_coefficient: float = 0.1



# Grid properties for optimization
var grid_size: float
var grid = {}
var grid_positions = []

# Particle properties
var velocities = []
var neighbors = []
var densities = []
var pressures = []
var forces = []
var prev_mouse_position = Vector2.ZERO

func _ready():
	_detect_multimesh_instance()
	calculate_grid_size()  # Calculate adaptive grid size
	initialize_multimesh()
	initialize_particles()
	apply_shader()  # Apply shader to particles

# Detect MultiMeshInstance2D node in the scene
func _detect_multimesh_instance():
	for child in get_children():
		if child is MultiMeshInstance2D and child.name == "FluidMultiMeshInstance2D":
			fluid_instance = child
			print("Detected FluidMultiMeshInstance2D.")

# Initialize the MultiMesh with particle mesh and set instance count
func initialize_multimesh():
	if fluid_instance:
		fluid_instance.multimesh = multimesh
		multimesh.transform_format = MultiMesh.TRANSFORM_2D
		multimesh.mesh = create_particle_mesh()
		fluid_instance.multimesh.instance_count = particle_count

# Create a mesh for each particle
func create_particle_mesh() -> Mesh:
	var particle_mesh := QuadMesh.new()
	particle_mesh.size = Vector2(particle_size, particle_size)
	return particle_mesh

# Apply a shader to the particles to visualize them better
func apply_shader():
	# Load the shader file
	var shader = load("res://shaders/Fluids.gdshader") as Shader
	var material = ShaderMaterial.new()
	material.shader = shader
	if fluid_instance:
		fluid_instance.material = material

# Calculate adaptive grid size based on interaction radius
func calculate_grid_size():
	grid_size = max(10.0, interaction_radius)

# Initialize particle positions, velocities, neighbors, densities, pressures, and forces
func initialize_particles():
	for i in range(particle_count):
		velocities.append(Vector2.ZERO)
		neighbors.append([])
		densities.append(rest_density)
		pressures.append(0.0)
		forces.append(Vector2.ZERO)
		grid_positions.append(Vector2.ZERO)

		var initial_pos = initialize_particle_position(i)
		set_particle_pos(i, initial_pos)
		velocities[i] = initialize_particle_velocity()

# Generate a random initial position for each particle
func initialize_particle_position(_index: int) -> Vector2:
	var random_x = randf_range(-boundary_size / 2, boundary_size / 2)
	var random_y = randf_range(-boundary_size / 2, boundary_size / 2)
	return Vector2(random_x, random_y)

# Generate a random initial velocity for each particle
func initialize_particle_velocity() -> Vector2:
	return Vector2(randf_range(-30, 30), randf_range(-30, 30))

# Set the position of a specific particle in the MultiMesh
func set_particle_pos(index: int, new_pos: Vector2):
	var local_transform := Transform2D()
	local_transform.origin = new_pos
	multimesh.set_instance_transform_2d(index, local_transform)

# Update grid with particle positions
func update_grid():
	grid.clear()
	for i in range(particle_count):
		var pos = multimesh.get_instance_transform_2d(i).origin
		var cell_x = int(pos.x / grid_size)
		var cell_y = int(pos.y / grid_size)
		var grid_pos = Vector2(cell_x, cell_y)
		grid_positions[i] = grid_pos
		if not grid.has(grid_pos):
			grid[grid_pos] = []
		grid[grid_pos].append(i)

# Get grid cell for a given position
func get_grid_cell(pos: Vector2) -> Vector2:
	return Vector2(floor(pos.x / grid_size), floor(pos.y / grid_size))

func poly6_kernel(distance: float, radius: float) -> float:
	if distance > radius:
		return 0.0
	var q = radius - distance
	return 315 / (64 * PI * pow(radius, 9)) * pow(q, 3)

func spiky_gradient_kernel(distance: float, radius: float) -> float:
	if distance > radius:
		return 0.0
	var q = radius - distance
	return -45 / (PI * pow(radius, 6)) * pow(q, 2)

func apply_surface_tension_force():
	for i in range(particle_count):
		var pos_i = multimesh.get_instance_transform_2d(i).origin
		var surface_tension_force = Vector2.ZERO
		for j in neighbors[i]:
			var pos_j = multimesh.get_instance_transform_2d(j).origin
			var distance = pos_i.distance_to(pos_j)
			if distance < interaction_radius and distance > 0:
				var direction = (pos_j - pos_i).normalized()
				var weight = poly6_kernel(distance, interaction_radius)
				surface_tension_force -= direction * surface_tension_coefficient * weight
		forces[i] += surface_tension_force


# Perform neighbor search using the grid
func update_neighbors():
	for i in range(particle_count):
		neighbors[i] = []  # Reset neighbors
		var grid_pos = grid_positions[i]
		var radius_squared = interaction_radius * interaction_radius

		# Iterate over neighboring grid cells
		for x_offset in [-1, 0, 1]:
			for y_offset in [-1, 0, 1]:
				var neighbor_cell = grid_pos + Vector2(x_offset, y_offset)
				if grid.has(neighbor_cell):
					for j in grid[neighbor_cell]:
						if i != j:
							var pos_i = multimesh.get_instance_transform_2d(i).origin
							var pos_j = multimesh.get_instance_transform_2d(j).origin
							var distance_squared = pos_i.distance_squared_to(pos_j)
							if distance_squared < radius_squared:
								neighbors[i].append(j)
		#print("Particle[", i, "] neighbors: ", len(neighbors[i]))

# Calculate densities and pressures for each particle
func calculate_density():
	var radius_squared = interaction_radius * interaction_radius
	for i in range(particle_count):
		var density = 0.0
		var pos_i = multimesh.get_instance_transform_2d(i).origin

		for j in neighbors[i]:
			var pos_j = multimesh.get_instance_transform_2d(j).origin
			var distance_squared = pos_i.distance_squared_to(pos_j)
			if distance_squared < radius_squared:
				density += particle_mass * poly6_kernel(sqrt(distance_squared), interaction_radius)

		densities[i] = density

		#print("Particle[", i, "] neighbors: ", neighbors[i].size())

func calculate_pressure():
	for i in range(particle_count):
		pressures[i] = stiffness * max(0, densities[i] - rest_density)

# Apply pressure forces to each particle
func apply_pressure_force(delta):
	for i in range(particle_count):
		var pos_i = multimesh.get_instance_transform_2d(i).origin
		var pressure_force = Vector2.ZERO

		for j in neighbors[i]:
			var pos_j = multimesh.get_instance_transform_2d(j).origin
			var distance = pos_i.distance_to(pos_j)
			if distance > 0 and distance < interaction_radius:
				var direction = (pos_i - pos_j).normalized()
				var force_magnitude = (pressures[i] + pressures[j]) / (2 * densities[j]) * spiky_gradient_kernel(distance, interaction_radius)
				pressure_force += direction * force_magnitude

		forces[i] += pressure_force
		#print("Pressure Force[", i, "]: ", pressure_force)

# Apply viscosity forces to each particle
func apply_viscosity_force(delta):
	for i in range(particle_count):
		var pos_i = multimesh.get_instance_transform_2d(i).origin
		var viscosity_force = Vector2.ZERO

		for j in neighbors[i]:
			var pos_j = multimesh.get_instance_transform_2d(j).origin
			var distance = pos_i.distance_to(pos_j)
			if distance < interaction_radius:
				var velocity_diff = velocities[j] - velocities[i]
				viscosity_force += velocity_diff * (1 - distance / interaction_radius)

		velocities[i] += viscosity * viscosity_force * delta

# Handle boundary collisions
func handle_boundary_collision(index: int, pos: Vector2):
	# Detect boundary collisions
	if pos.x < -boundary_size:
		pos.x = -boundary_size
		velocities[index].x = -velocities[index].x * velocity_damping
	elif pos.x > boundary_size:
		pos.x = boundary_size
		velocities[index].x = -velocities[index].x * velocity_damping

	if pos.y < -boundary_size:
		pos.y = -boundary_size
		velocities[index].y = -velocities[index].y * velocity_damping * 0.5
	elif pos.y > boundary_size:
		pos.y = boundary_size
		velocities[index].y = -velocities[index].y * velocity_damping * 0.5

	# Update the particle position
	set_particle_pos(index, pos)

#func track_velocity():
	#if particle_count > 0:  # Check a single particle as an example
		#print("Velocity[0]: ", velocities[0])


# Apply mouse interaction forces to particles
func apply_mouse_force(mouse_position: Vector2, prev_mouse_position: Vector2):
	var cursor_dx = mouse_position.x - prev_mouse_position.x
	var cursor_dy = mouse_position.y - prev_mouse_position.y

	for i in range(particle_count):
		var pos = multimesh.get_instance_transform_2d(i).origin
		var distance = pos.distance_to(mouse_position)

		if distance < mouse_interaction_radius:
			var strength = max(0, 1 - distance / mouse_interaction_radius)
			velocities[i].x += strength * cursor_dx
			velocities[i].y += strength * cursor_dy

func split_clipped_particles():
	for i in range(particle_count):
		for j in neighbors[i]:
			var pos_i = multimesh.get_instance_transform_2d(i).origin
			var pos_j = multimesh.get_instance_transform_2d(j).origin
			var distance = pos_i.distance_to(pos_j)

			if distance < particle_size * 1.5:  # Threshold for overlap
				resolve_clipping(i, j, distance)

func resolve_clipping(index_a: int, index_b: int, distance: float):
	if distance > 0:  # Avoid division by zero
		var pos_a = multimesh.get_instance_transform_2d(index_a).origin
		var pos_b = multimesh.get_instance_transform_2d(index_b).origin
		var direction = (pos_b - pos_a).normalized()
		var overlap = particle_size * 1.5 - distance
		var separation = direction * overlap * 0.5

		# Distribute separation
		pos_a -= separation
		pos_b += separation

		set_particle_pos(index_a, pos_a)
		set_particle_pos(index_b, pos_b)

func apply_repulsion_force(delta):
	var radius_squared = interaction_radius * interaction_radius
	for i in range(particle_count):
		var pos_i = multimesh.get_instance_transform_2d(i).origin

		for j in neighbors[i]:
			var pos_j = multimesh.get_instance_transform_2d(j).origin
			var distance_squared = pos_i.distance_squared_to(pos_j)
			if distance_squared < radius_squared and distance_squared > 0:
				var distance = sqrt(distance_squared)
				var direction = (pos_i - pos_j).normalized()
				var overlap = interaction_radius - distance
				var repulsion_force = direction * overlap * 50.0  # Reduced strength
				velocities[i] += repulsion_force * delta * 0.5  # Scale down effect

func apply_gravity():
	for i in range(particle_count):
		velocities[i] += gravity


# Main simulation loop
func _process(delta):
	#track_velocity()  # Track the first particle's velocity
	update_grid()  # Update the grid for this frame
	update_neighbors()  # Find neighbors using the grid
	calculate_density()  # Compute densities
	calculate_pressure()  # Compute pressures based on updated densities
	apply_gravity()  # Apply gravity to particles
	apply_surface_tension_force()  # Apply surface tension forces
	apply_pressure_force(delta)  # Apply pressure forces
	apply_viscosity_force(delta)  # Apply viscosity forces
	apply_repulsion_force(delta)  # Apply repulsion force

	# Mouse interaction
	var mouse_pos = get_global_mouse_position()
	apply_mouse_force(mouse_pos, prev_mouse_position)
	prev_mouse_position = mouse_pos

	# Update particle positions and handle boundary collisions
	for i in range(particle_count):
		var pos_i = multimesh.get_instance_transform_2d(i).origin
		pos_i += velocities[i] * delta
		handle_boundary_collision(i, pos_i)

	# Resolve any overlapping particles
	split_clipped_particles()
