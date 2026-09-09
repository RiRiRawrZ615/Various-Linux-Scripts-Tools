# Heroic Library Tools
These are meant to help make the use of Heroic Launcher easier in Linux when moving to new machines or if your game library is Massive.

## 🎮 Heroic Library Linker
This script manages your Heroic library. It handles standard symlinking for general folders and features a GOG Intelligent Import that automatically registers GOG IDs into the Heroic Master List and generates corresponding Wine/Proton configuration files. It creates a `SymGames` folder based on your list to handle these links.

## 🔍 Windows User Discovery
This tool works in tandem with the linker by scanning mounted drives for valid Windows user directories. Once found, it updates the symlink within your shared Heroic Wine/Proton prefix to ensure your files are mapped correctly. This particular script is meant to be autorun at boot, but you could run it manually if you wished to.

**Note:** Some paths, such as the user directory, are currently hardcoded. You will need to perform a hostname or username change in the scripts to ensure they work correctly on your specific system.
