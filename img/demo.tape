# Renders the README demo GIF: img/demo.gif
# Usage: vhs img/demo.tape   (run from repo root)
Output "img/demo.gif"
Set Shell bash
Set FontFamily "JetBrainsMono Nerd Font"
Set FontSize 22
Set Width 1500
Set Height 900
Set Padding 50
Set Theme "Catppuccin Mocha"
Set BorderRadius 12
Set Margin 30
Set MarginFill "#1e1e2e"
Set TypingSpeed 45ms
Set PlaybackSpeed 1.0

Hide
Type "clear" Enter
Show
Sleep 500ms

Type "# NVIDIA DGX Spark (GB10) · headless 4K remote desktop"
Sleep 400ms
Enter
Type "# one installer: Sunshine + Moonlight + NVENC, no dummy plug"
Sleep 400ms
Enter
Enter
Sleep 600ms

Type "./install.sh --help"
Sleep 300ms
Enter
Sleep 2500ms

Type "bash img/status-demo.sh"
Sleep 300ms
Enter
Sleep 3500ms
