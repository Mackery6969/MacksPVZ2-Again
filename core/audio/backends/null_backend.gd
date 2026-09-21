extends AudioBackend
## Does nothing, audibly. The default until an audio backend is installed, so
## the game is fully playable and testable with no sound stack present.

func backend_name() -> String:
	return "silent"
