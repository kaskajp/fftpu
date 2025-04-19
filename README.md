# FFTPU - FTP Upload Menu Bar Tool

FFTPU (FTP Upload) is a macOS menu bar tool that allows you to quickly upload files to an FTP server and get back a URL to the file.

## Features

- Upload files to an FTP server with a simple drag and drop interface
- Automatically copy the URL to the clipboard when the upload is complete
- View recent uploads and their status
- Configure FTP server settings including:
  - FTP server URL
  - FTP username
  - FTP password
  - FTP port
  - SFTP or FTP option
  - Web server URL for file access

## Requirements

- macOS 15.0 or later
- Xcode 16.0 or later for development

## How to Use

1. **First Time Setup**: Click on the gear icon in the app menu bar to open settings. Enter your FTP server details including:
   - SFTP server URL (e.g., `sftp.example.com`)
   - Username and password
   - Port number (default is 22 for SFTP)
   - Web server URL where files will be accessible (e.g., `https://example.com/uploads/`)

2. **Uploading Files**: 
   - Drag and drop a file onto the menu bar icon, or click the plus button
   - The file will be uploaded to your FTP server
   - When complete, the URL will be automatically copied to your clipboard

3. **Recent Uploads**:
   - View recent uploads in the menu
   - Click on any completed upload to copy its URL to the clipboard

## How It Works

FFTPU uses the `curl` command line tool to handle SFTP uploads. The app provides a simple user interface to configure the FTP server settings and upload files, then handles the connection and transfer process in the background.

## Troubleshooting

- If uploads fail, check your SFTP server credentials and connection details
- Make sure your web server URL is correctly configured to access the uploaded files
- Check that your SFTP server allows uploads to the specified directory
