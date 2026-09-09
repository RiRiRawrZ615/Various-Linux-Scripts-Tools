# Heroic Library Tools

## 🎮 Heroic Library Linker
This script manages your Heroic library. It handles standard symlinking for general folders and features a GOG Intelligent Import that automatically registers GOG IDs into the Heroic Master List and generates corresponding Wine/Proton configuration files [1]. It creates a `SymGames` folder based on your list to handle these links.

## 🔍 Windows User Discovery
This tool works in tandem with the linker by scanning mounted drives for valid Windows user directories. Once found, it updates the symlink within your shared Heroic Wine/Proton prefix to ensure your files are mapped correctly [2].

**Note:** Some paths, such as the user directory, are currently hardcoded. You will need to perform a hostname or username change in the scripts to ensure they work correctly on your specific system.
