#Load PowerCLI Modules
if ( !(Get-Module -Name VMware.VimAutomation.Core -ErrorAction SilentlyContinue) ) {
. 'C:\Program Files (x86)\VMware\Infrastructure\PowerCLI\Scripts\Initialize-PowerCLIEnvironment.ps1'
}

#Connect to vCenter at Site A
Connect-VIServer vcsa-01a.corp.local -User administrator@vsphere.local  -Password VMware1!


#Start K8s Nodes if not already started.
$PoweredOffK8sVMs = Get-VM -Name k8s* | where {$_.PowerState -eq "PoweredOff"}
if ($PoweredOffK8sVMs -ne $null) {
Get-VM -Name $PoweredOffK8sVMs | Start-VM -Confirm:$false
}

#Create new object for the opaque network to properly configure the port group setting on a virtual machine.
function Set-NetworkAdapterOpaqueNetwork {
param(
    [Parameter(Mandatory = $true, ValueFromPipeline = $true, Position = 1)]
    [VMware.VimAutomation.Types.NetworkAdapter]
    $NetworkAdapter,

    [Parameter(Mandatory = $true, Position = 2)]
    [string]
    $OpaqueNetworkName,

    [Parameter()]
    [switch]
    $Connected,

    [Parameter()]
    [switch]
    $StartConnected
)
process {
    $opaqueNetwork = Get-View -ViewType OpaqueNetwork | ? {$_.Name -eq $OpaqueNetworkName}
    if (-not $opaqueNetwork) {
        throw "'$OpaqueNetworkName' network not found."
    }

    $opaqueNetworkBacking = New-Object VMware.Vim.VirtualEthernetCardOpaqueNetworkBackingInfo
    $opaqueNetworkBacking.OpaqueNetworkId = $opaqueNetwork.Summary.OpaqueNetworkId
    $opaqueNetworkBacking.OpaqueNetworkType = $opaqueNetwork.Summary.OpaqueNetworkType

    $device = $NetworkAdapter.ExtensionData
    $device.Backing = $opaqueNetworkBacking

    if ($StartConnected) {
        $device.Connectable.StartConnected = $true
    }

    if ($Connected) {
        $device.Connectable.Connected = $true
    }
    
    $spec = New-Object VMware.Vim.VirtualDeviceConfigSpec
    $spec.Operation = [VMware.Vim.VirtualDeviceConfigSpecOperation]::edit
    $spec.Device = $device
    $configSpec = New-Object VMware.Vim.VirtualMachineConfigSpec
    $configSpec.DeviceChange = @($spec)
    $NetworkAdapter.Parent.ExtensionData.ReconfigVM($configSpec)

    # Output
    Get-NetworkAdapter -Id $NetworkAdapter.Id
    }
}


#Set K8s Node VIF interface
Get-VM -Name k8s-master | Get-NetworkAdapter -Name "Network adapter 2" | Set-NetworkAdapterOpaqueNetwork -OpaqueNetworkName "tenant1-k8s-node-vif" -Connected:$true
Get-VM -Name k8s-node1 | Get-NetworkAdapter -Name "Network adapter 2" | Set-NetworkAdapterOpaqueNetwork -OpaqueNetworkName "tenant1-k8s-node-vif" -Connected:$true
Get-VM -Name k8s-node2 | Get-NetworkAdapter -Name "Network adapter 2" | Set-NetworkAdapterOpaqueNetwork -OpaqueNetworkName "tenant1-k8s-node-vif" -Connected:$true
