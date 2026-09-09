# Various-Linux-Scripts-Tools

This repository is a collection of various scripts and utilities I have developed throughout this year.

## 📖 The Backstory

This project grew out of my transition away from Windows. As Windows became increasingly cumbersome and frustrating, I made the move to **Nobara KDE**. While Nobara provides a similar desktop experience, it lacks some of the specific, niche automations I found myself needing to make my workflow feel seamless. (And while I love the environment, I still have my fair share of headaches with GRUB).

The philosophy behind this repository is simple: **Automation.** 

I realized that many of the tasks I was performing were repetitive. By writing scripts to handle them, I could save time and reduce the mental load of managing my system. Most of these tools are designed as "one-time setup" solutions. This is especially important for complex environments like LLMs; since there isn't a single standardized way to set them up, having a template or a starting point makes the process much easier.

> [!NOTE]
> This is a living repository. I will continue to add new tools as I create them and update existing ones whenever I release new versions for the end user. Because this is my personal toolkit, the contents and structure may change at any point.

## 📂 Repository Modules

The repository is organized into specialized modules. Each module contains its own dedicated tools and documentation.

* **[AI](./AI/)**: Specialized launchers and database repair tools for managing OpenWebUI and SillyTavern environments.
* **[Display-FS-Misc](./Display-FS-Misc/)**: System utilities for handling NTFS mounting, display resolution toggles, and dual-boot management.
* **[Heroic-Launcher](./Heroic-Launcher/)**: Tools specifically for the Heroic Games Launcher to assist with library linking and GOG imports.
* **[SyncSavesTool](./SyncSavesTool/)**: A cross-platform synchronization engine designed to safely backup and restore game saves between Linux and Windows.

## 🛠️ Technical Approach

Most tools in this repository are built to be "set it and forget it." Once you have performed the initial configuration (such as setting your hostname or path mappings), the scripts handle the heavy lifting, allowing you to focus on using your tools rather than managing them.

---
*Maintained by [RiRiRawrZ615](https://github.com/RiRiRawrZ615)*
