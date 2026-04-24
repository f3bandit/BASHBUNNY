# Bash Bunny Jessie Offline Package System

A reproducible offline package system for the Hak5 Bash Bunny (Debian Jessie armhf).

This project restores a working package manager, fixes dependency issues, and provides a trimmed, practical toolset for development, debugging, and networking.

---

## Overview

The Bash Bunny ships with an outdated Debian Jessie environment. Because Jessie is end-of-life, package repositories are no longer maintained, which causes:

- Broken `apt-get`
- Failed dependency resolution
- Incomplete or inconsistent installs
- Inability to install new tools reliably

This project solves those issues by creating a local package repository and installing packages in a controlled, dependency-aware way.

---

## What This Fixes

- Restores a working package system
- Enables offline installs after initial setup
- Eliminates `dpkg` dependency errors
- Fixes broken system packages (e.g. `procps`, `udev`)
- Provides a stable, repeatable environment

---

## How It Works

1. Downloads Debian Jessie armhf packages from the archived repository
2. Caches all required `.deb` files locally
3. Builds a local APT repository on the Bunny
4. Installs only a trimmed set of useful packages
5. Uses APT to resolve dependencies in the correct order

---

## Installed Package Set

### Build Tools
- build-essential
- gcc
- g++
- make
- libc6-dev
- pkg-config
- autoconf
- automake
- libtool
- patch
- perl
- python
- dpkg
- dpkg-dev
- fakeroot

### Core Utilities
- tar
- gzip
- bzip2
- xz-utils
- unzip
- file
- wget
- curl
- ca-certificates

### Networking Tools
- iproute2
- iptables
- net-tools
- iputils-ping
- arping
- netcat-openbsd
- tcpdump
- nmap
- socat

### Diagnostics / Shell
- tmux
- htop
- lsof
- strace
- pv
- vim-tiny
- vim-common
- nano

### Analysis
- radare2

---

## Package Source

Packages are sourced from:

http://archive.debian.org/debian

Architecture:

armhf (ARMv7)

Packages are stored in this repository under:

jessie-armhf-debs/

---

## Usage

### 1. Copy Script to Bunny
