# Renders the README "verified" still: img/verified.png
# Usage: vhs img/verified.tape   (run from repo root)
Output "img/_verified_tmp.gif"
Set Shell bash
Set FontFamily "JetBrainsMono Nerd Font"
Set FontSize 22
Set Width 1340
Set Height 600
Set Padding 44
Set Theme "Catppuccin Mocha"
Set BorderRadius 12
Set Margin 30
Set MarginFill "#1e1e2e"

Hide
Type "bash img/status-demo.sh" Enter
Sleep 1200ms
Show
Screenshot "img/verified.png"
Sleep 200ms
