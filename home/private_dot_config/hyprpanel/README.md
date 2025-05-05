
## CPU TEMP

```bash
 for i in /sys/class/hwmon/hwmon*/temp*_input; do echo "$(<$(dirname $i)/name): $(cat ${i%_*}_label 2>/dev/null || echo $(basename ${i%_*})) $(readlink -f $i)"; done
nvme: Composite /sys/devices/pci0000:00/0000:00:01.1/0000:01:00.0/nvme/nvme0/hwmon0/temp1_input
nvme: Composite /sys/devices/pci0000:00/0000:00:01.2/0000:02:00.0/0000:03:01.0/0000:04:00.0/nvme/nvme1/hwmon1/temp1_input
nvme: Sensor 1 /sys/devices/pci0000:00/0000:00:01.2/0000:02:00.0/0000:03:01.0/0000:04:00.0/nvme/nvme1/hwmon1/temp2_input
nvme: Sensor 2 /sys/devices/pci0000:00/0000:00:01.2/0000:02:00.0/0000:03:01.0/0000:04:00.0/nvme/nvme1/hwmon1/temp3_input
# this one for limon:
k10temp: Tctl /sys/devices/pci0000:00/0000:00:18.3/hwmon/hwmon2/temp1_input
k10temp: Tccd1 /sys/devices/pci0000:00/0000:00:18.3/hwmon/hwmon2/temp3_input
k10temp: Tccd2 /sys/devices/pci0000:00/0000:00:18.3/hwmon/hwmon2/temp4_input
asusec: Chipset /sys/devices/platform/asus-ec-sensors/hwmon/hwmon4/temp1_input
asusec: CPU /sys/devices/platform/asus-ec-sensors/hwmon/hwmon4/temp2_input
asusec: Motherboard /sys/devices/platform/asus-ec-sensors/hwmon/hwmon4/temp3_input
asusec: T_Sensor /sys/devices/platform/asus-ec-sensors/hwmon/hwmon4/temp4_input
asusec: VRM /sys/devices/platform/asus-ec-sensors/hwmon/hwmon4/temp5_input
```

## Clock Format
NEW
```
    %a %m/%d %H:%M
```
ORIG
```
    %a %b %d  %I:%M:%S %p
```
