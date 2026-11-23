extends Resource
## Stand-in for the developer's terrain material bank script, which the source release leaves out
## (tools/ is not shipped). world/terrain/gaea/surfaces.res names it as its script; with this, source
## runs load the bank (texture images and their mean colours) and the ground gets its real textures.
@export var images: Array[Image] = []
@export var means: PackedVector3Array = PackedVector3Array()
