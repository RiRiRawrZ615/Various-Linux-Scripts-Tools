# AI Management Suite

This directory serves as a centralized management hub for your AI-driven environments. It is designed to provide specialized launcher, repair, and synchronization tools for managing OpenWebUI and SillyTavern installations.

## 📂 Directory Layout

| Folder | Description |
| :--- | :--- |
| `OpenWebUI/` | Tools for OpenWebUI database repair, migration, and launching. |
| `SillyTavern/` | Launcher and sync tools for SillyTavern environments [1]. |
| `Backup Tool/` | Utilities for syncing and backing up AI configuration and data. |

## 🛠️ Overview

This suite is intended to handle the "messy" side of running local AI, including:

* **Environment Bootstrapping:** Launching servers with correct GPU/ROCm parameters [1].
* **Data Integrity:** Repairing and migrating databases to prevent corruption during moves.
* **Safe Synchronization:** Backing up critical character and chat data without bloating the backup with unnecessary cache files.
