# Sync Saves Tool

Managing game saves shouldn't be a gamble. While services like GOG, Steam, and other digital storefronts offer cloud saving, they are notoriously unreliable. Cloud syncs can fail to upload, overwrite newer local files with older cloud data, or miss specific files entirely. 

The **Sync Saves Tool** was created to provide an intentional, manual alternative. Unlike tools like Syncthing, which act as continuous, heavy-duty background services, this tool is designed to be lightweight and on-demand. It is meant for users who want absolute control, allowing you to trigger a backup or restore only when you decide to.

## 🐧 Linux Version

The Linux implementation is built for flexibility and caters to different user workflows. It supports:

* **TUI (Text User Interface):** Uses `whiptail` to provide a clean, terminal-based interface for users who prefer staying in the command line.
* **Zenity GUI:** A lightweight graphical interface for users who want a simple, mouse-driven experience without the overhead of a full desktop application.

## 🪟 Windows Version

The Windows version was developed later in response to direct user requests. It is a dedicated **WinForms** application designed to bring the same synchronization power to Windows users. 

**Note:** Unlike the Linux version, the Windows version is currently GUI-only and does not yet feature a non-GUI/command-line mode.

## 🔄 The Cross-Platform Bridge: Path Translation

The most powerful feature of this suite is its ability to share a single configuration across different operating systems. 

To allow users to use the exact same `game_save_sync_list.txt` on both Linux and Windows, the Windows version includes a specialized **Path Translation Engine**. This engine detects Linux or Wine-style paths, and using a seperate .cfg file, maps them to your specific Windows directory structure. This ensures that you can manage your saves on one platform and restore them on another without having to rewrite your game saves list. In addition, this allows you to select the NAS folder in the Windows release.
