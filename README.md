# Disks

A Mac menu bar app for unlocking your drives with Touch ID.

## Rationale

I have a Samsung T7 and WD Blue SN5000 I bought before AI companies exploded the price by 3x and 1.5x, respectively. When I connect my SN5000, I’m asked to enter a password to unlock one of the disks I created.

<details>
  <summary>Enter a password to unlock the disk “SN5000”.</summary>

  <img src="Documentation/Screenshot 2026-07-21 at 5.12.22 PM.png">
</details>

This is fine, but involves me finding the password in my password manager to paste and unlock, which is tedious when done almost daily. I can ask it to remember my password, but that allows anyone using my device to access the disk by connecting the drive. The same issue applies to encrypted disk images. If I unmount the disk, I’ll need to use an app like Disk Utility to remount it.

There are apps like [Semulov](https://github.com/kainjow/Semulov) and [MountMate](https://github.com/homielab/mountmate) which ease the process, but [the former is in maintenance mode](https://github.com/kainjow/Semulov/issues/47), and neither addresses the issue of anyone being able to connect my drive for access, nor supports opening disk images.

Enter Disks, a menu bar app for unlocking your drives with Touch ID.

<details>
  <summary>Disks is trying to unlock the disk “SN5000”.</summary>

  <img src="Documentation/Screenshot 2026-07-21 at 6.04.40 PM.png">
</details>

## Download

> [!IMPORTANT]
>
> Disks has not been notarized by Apple. To run the app, open it and [follow these instructions](https://support.apple.com/en-us/102445#openanyway).

You can download a release from the [Releases](https://github.com/kyleerhabor/disks/releases) page.

macOS Sequoia 15 or later is required.
