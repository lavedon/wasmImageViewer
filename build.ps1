# Build viewer.wasm with zig-as-C-compiler (no Emscripten, no libc).
# Zig lives in C:\my-coding-projects\tools; override with $env:ZIG.

$zig = $env:ZIG ?? "C:\my-coding-projects\tools\zig-x86_64-windows-0.16.0\zig.exe"

& $zig cc -target wasm32-freestanding -O2 -nostdlib -Ishim `
    "-Wl,--no-entry" `
    "-Wl,-z,stack-size=1048576" `
    -o viewer.wasm viewer.c

if ($LASTEXITCODE -eq 0) {
    Write-Host "OK: viewer.wasm $((Get-Item viewer.wasm).Length) bytes"
    Write-Host "Serve locally with: python -m http.server 8080"
} else {
    exit $LASTEXITCODE
}
