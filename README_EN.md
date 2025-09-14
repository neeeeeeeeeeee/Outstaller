# Outstaller

<p align="center">
    <img src="Outstaller.png" alt="Logo" width="120" />
</p>

[中文](./README.md) | English
<hr/>

Outstaller is a simple and efficient macOS application installer designed to provide users with a smooth installation experience, supporting the installation of .app files anywhere, including external storage devices.

## Features

- One-click app installation
- Clean and intuitive user interface
- Secure permission management
- Supports replacing and updating existing applications

## Installation

1. Clone this repository:
2. Open `Outstaller.xcodeproj` with Xcode
3. Build and run the project

## Usage

### Install Applications

- Launch the Outstaller app.
- On first launch, select the destination path for storing `.app` files (this can be changed anytime via the gear icon in the top right corner).
- Drag and drop `.app` files into the window to copy them to the selected location and automatically create a symbolic link in the system Applications folder.

### Uninstall Applications

- It is recommended to use [AppCleaner](https://freemacsoft.net/appcleaner/) for thorough removal of apps and their related files.
- When uninstalling, please also remove the symbolic link in the system Applications folder to avoid leftover shortcuts.

## Contributing

Contributions are welcome! Please follow these steps:

1. Fork this repository
2. Create a new branch
3. Commit your changes
4. Push to the branch
5. Create a Pull Request

## License

MIT License