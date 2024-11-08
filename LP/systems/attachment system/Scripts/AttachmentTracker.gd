@tool
extends Node
class_name AttachmentTracker

@export var socket_stack_pairs: Dictionary = {}
@export var skeleton : Skeleton2D


func new_socket(socket : AttachmentSocket):
	if not socket or socket_stack_pairs.has(socket):
		return
	if not socket.tree_exited.is_connected(remove_socket):
		socket.tree_exited.connect(remove_socket.bind(socket))
	add_stack_for_socket(socket)
	ensure_socket_stack_pairs()


func remove_socket(socket: AttachmentSocket):
	# Clear the entity association
	socket.update_state()
	
	# Log the removal for debugging
	print("User removed a socket: " + socket.name)
	
	# Remove the socket from stack pairs if it exists
	if socket in socket_stack_pairs:
		remove_stack_for_socket(socket)
		socket_stack_pairs.erase(socket)
	else:
		print("Attempted to remove a non-existent socket from stack pairs: " + socket.name)
	# Ensure integrity of socket-stack pairs after removal
	ensure_socket_stack_pairs()


func add_stack_for_socket(socket: AttachmentSocket):
	# Only create a stack if the socket doesn't already have one
	var new_stack
	if socket.IK_type == AttachmentSocket.IK_chain_type.CCDIK:
		new_stack = SkeletonModification2DCCDIK.new()
	elif socket.IK_type == AttachmentSocket.IK_chain_type.FABRIK:
		new_stack = SkeletonModification2DFABRIK.new()
	skeleton.get_modification_stack().add_modification(new_stack)
	socket_stack_pairs[socket] = new_stack
	print("Added new stack for socket:", socket.name + "with type: " + str(socket.IK_type))


# Function to maintain pairs and keep them synchronized
func ensure_socket_stack_pairs():
	var mod_stack = skeleton.get_modification_stack()
	# Check for stale pairs (remove stacks if their socket no longer exists)
	for socket : AttachmentSocket in socket_stack_pairs.keys():
		var stack = socket_stack_pairs[socket]
		if stack == null or not is_instance_valid(stack):
			add_stack_for_socket(socket)
			push_warning("Socket lacked a stack, adding")
	for i in mod_stack.modification_count:
		if not socket_stack_pairs.values().has(mod_stack.get_modification(i)):
			mod_stack.get_modification(i).free()
	# Warning if still not matched, but shouldn’t happen with this setup
	if mod_stack.modification_count != socket_stack_pairs.size():
		print("Warning: Modifications and sockets are not fully synchronized.")
	else:
		print("Corrected mod stack count")


func remove_stack_for_socket(socket: AttachmentSocket):
	# Remove the stack if it exists in the dictionary
	if socket_stack_pairs.has(socket):
		var stack_to_remove: SkeletonModification2D = socket_stack_pairs[socket]
		var modification_stack = skeleton.get_modification_stack()
		for i in skeleton.get_modification_stack().modification_count:
			var current_stack = modification_stack.get_modification(i)
			if current_stack == stack_to_remove:
				# Remove the modification at the found index
				modification_stack.delete_modification(i)
				print("Removed stack for socket:", socket.name)
				break  # Exit loop after deletion to avoid errors
		# Remove the socket entry from the dictionary
		socket_stack_pairs.erase(socket)
	else:
		push_error("Socket not found in socket_stack_pairs. No stack to remove.")


func update_ik_types():
	# Loop through each socket-modification pair in the dictionary
	for socket : AttachmentSocket in socket_stack_pairs.keys():
		var current_stack : SkeletonModification2D = socket_stack_pairs[socket]
		## Check if the stack type matches the socket's IK_type
		var correct_stack_type = null
		match socket.IK_type:
			socket.IK_chain_type.CCDIK:
				if not current_stack is SkeletonModification2DCCDIK:
					correct_stack_type = SkeletonModification2DCCDIK.new()
			socket.IK_chain_type.FABRIK:
				if not current_stack is SkeletonModification2DFABRIK:
					correct_stack_type = SkeletonModification2DFABRIK.new()

		## If we have determined stack is wrong. Change it
		if correct_stack_type:
			var modification_stack = skeleton.get_modification_stack()
			for i in modification_stack.modification_count:
				var i_stack = modification_stack.get_modification(i)
				if i_stack == current_stack:
					modification_stack.delete_modification(i)
					modification_stack.add_modification(correct_stack_type)
					socket_stack_pairs[socket] = correct_stack_type
					print("Stack updated")
	update_stacks_with_occupied_parts()


# Update each socket-modification stack with the occupied part’s skeleton index
func update_stacks_with_occupied_parts():
	for socket in socket_stack_pairs:
		var stack = socket_stack_pairs[socket]
		if not stack:
			continue
		if socket.my_entity == null:
			nullify_stack(stack)
			continue
		#Check the entity is correct
		var occupying_part = socket.my_entity
		if not occupying_part is Bone2D:
			push_warning("Ineligible part in socket")
			continue
		#Perform update on skeleton
		var chain_length = get_chain_length(occupying_part)
		if stack is SkeletonModification2DCCDIK:
			update_ccdik(occupying_part, stack, chain_length)
		elif stack is SkeletonModification2DFABRIK:
			update_fabrik(occupying_part, stack, chain_length)
		else:
			push_warning("Stack type not recognized")


func nullify_stack(stack):
	if stack is SkeletonModification2DCCDIK:
		stack.ccdik_data_chain_length = 0
	elif stack is SkeletonModification2DFABRIK:
		stack.fabrik_data_chain_length = 0


func update_ccdik(first_bone, stack : SkeletonModification2DCCDIK, chain_length : int):
	stack.ccdik_data_chain_length = chain_length
	# Traverse through the bone chain to set joint indices in the stack
	var current_bone : Bone2D = first_bone
	for i in range(chain_length):
		if current_bone:
			#Set value of new joint and assign next bone
			stack.set_ccdik_joint_bone_index(i, current_bone.get_index_in_skeleton())
			if stack.get_ccdik_joint_bone_index(i) == -1:
				push_warning("Chain Length is wrong!")
				stack.ccdik_data_chain_length = 0
				break
			current_bone = next_bone_in_chain(current_bone)


func next_bone_in_chain(current_bone : Node2D) -> Node2D:
	var new_bone = null
	for i in current_bone.get_children():
		if i is Bone2D:
			new_bone = i
	return new_bone


func update_fabrik(first_bone, stack : SkeletonModification2DFABRIK, chain_length : int):
	stack.fabrik_data_chain_length = chain_length
	# Traverse through the bone chain to set joint indices in the stack
	var current_bone : Bone2D = first_bone
	for i in range(chain_length):
		if current_bone:
			#Set value of new joint
			stack.set_fabrik_joint_bone_index(i, current_bone.get_index_in_skeleton())
			#Check that we set the value correctly!
			if stack.get_fabrik_joint_bone_index(i) == -1:
				push_warning("Chain indicies are wrong!")
			# Move to the next bone in the chain
			current_bone = next_bone_in_chain(current_bone)


 #Find the closest socket to a given entity
func find_closest_socket(entity: EntityPart, distance) -> AttachmentSocket:
	var closest_socket: AttachmentSocket = null
	var closest_dist = distance
	for socket : AttachmentSocket in socket_stack_pairs:
		if not socket.enabled or socket.my_entity:
			continue
		var dist = entity.global_position.distance_to(socket.global_position)
		if dist < closest_dist:
			closest_dist = dist
			closest_socket = socket
	return closest_socket


# Helper function to calculate the chain length recursively
func get_chain_length(bone: Bone2D) -> int:
	var length : int = 1  # Start with 1 to count the current bone
	for i in range(bone.get_child_count()):
		var child = bone.get_child(i)
		if child is Bone2D:
			length += get_chain_length(child)  # Add child chain lengths recursively
	return length
