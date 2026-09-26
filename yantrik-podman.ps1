<#
.SYNOPSIS
    Podman Compose launcher for Yantrik OS on Windows 11 + WSL2.
.DESCRIPTION
    Ensures the target WSL2 Podman machine is running, loads the KVM kernel module
    (kvm_intel or kvm_amd), configures /dev/kvm permissions (persisting udev and
    modules-load rules inside the Podman machine), and runs podman compose inside
    the Linux VM.

    Pass 'setup' to automatically download/verify yantrik.iso and start the stack.
#>
$ErrorActionPreference = 'Stop'

$composeArgs = @(if ($args.Count) { $args } else { 'ps' })
$isSetup = ($composeArgs.Count -eq 1 -and $composeArgs[0] -eq 'setup')
if ($isSetup) {
    & (Join-Path $PSScriptRoot 'scripts\download-iso.ps1')
    $composeArgs = @('up', '-d')
}

$podmanCommand = Get-Command podman.exe -ErrorAction SilentlyContinue
$podman = if ($podmanCommand) { $podmanCommand.Source } else { 'C:\Program Files\RedHat\Podman\podman.exe' }
if (-not (Test-Path -LiteralPath $podman)) {
    throw 'Podman executable not found. Install Podman Desktop / Podman CLI for Windows first.'
}

$rawJson = & $podman machine list --format json | Out-String
$parsed = if ($rawJson.Trim()) { $rawJson | ConvertFrom-Json } else { @() }
$machines = @($parsed | ForEach-Object { $_ })

$defaultMachine = $machines | Where-Object { $_.Default -eq $true } | Select-Object -First 1
$openmausbot = $machines | Where-Object { $_.Name -and $_.Name.TrimEnd('*') -eq 'openmausbot' } | Select-Object -First 1

$machine = if ($env:YANTRIK_PODMAN_MACHINE) {
    $env:YANTRIK_PODMAN_MACHINE
} elseif ($defaultMachine) {
    [string]$defaultMachine.Name.TrimEnd('*')
} elseif ($openmausbot) {
    'openmausbot'
} elseif ($machines.Count -gt 0 -and $machines[0].Name) {
    [string]$machines[0].Name.TrimEnd('*')
} else {
    'podman-machine-default'
}

$selected = $machines | Where-Object { $_.Name -and $_.Name.TrimEnd('*') -eq $machine } | Select-Object -First 1
if (-not $selected) {
    Write-Host "==> Initializing Podman machine '$machine' ..." -ForegroundColor Cyan
    & $podman machine init $machine
    $rawAfter = & $podman machine list --format json | Out-String | ConvertFrom-Json
    $selected = @($rawAfter | ForEach-Object { $_ }) | Where-Object { $_.Name -and $_.Name.TrimEnd('*') -eq $machine } | Select-Object -First 1
}

if (-not $selected.Running) {
    Write-Host "==> Starting Podman machine '$machine' ..." -ForegroundColor Cyan
    $res = Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{
        CommandLine = "`"$podman`" machine start $machine"
    }
    while (Get-Process -Id $res.ProcessId -ErrorAction SilentlyContinue) {
        Start-Sleep -Seconds 1
    }
}

$kvmInitCmd = @(
    'sudo modprobe kvm_intel 2>/dev/null || sudo modprobe kvm_amd 2>/dev/null || true',
    'sudo chmod 666 /dev/kvm',
    'printf "kvm\nkvm_intel\nkvm_amd\n" | sudo tee /etc/modules-load.d/kvm.conf >/dev/null',
    'printf "KERNEL==\"kvm\", GROUP=\"kvm\", MODE=\"0666\"\n" | sudo tee /etc/udev/rules.d/99-kvm.rules >/dev/null'
) -join '; '
& $podman machine ssh $machine $kvmInitCmd

function Quote-Posix([string]$value) {
    return "'" + $value.Replace("'", "'\''") + "'"
}

if ($PSScriptRoot -notmatch '^([A-Za-z]):\\(.+)$') {
    throw 'Place this repository on a local Windows drive letter accessible to WSL2 (/mnt/<drive>).'
}

$linuxProject = '/mnt/' + $Matches[1].ToLower() + '/' + $Matches[2].Replace('\', '/')
$quotedProject = Quote-Posix $linuxProject

$command = 'cd ' + $quotedProject + ' && PODMAN_COMPOSE_PROVIDER=/usr/bin/podman-compose podman compose -f compose.yaml ' + (($composeArgs | ForEach-Object { Quote-Posix $_ }) -join ' ')
& $podman machine ssh $machine $command
exit $LASTEXITCODE
