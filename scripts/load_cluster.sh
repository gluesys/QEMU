#!/bin/bash

#######  Constant Setting ######

NUMA_CMD="numactl -C"
GVM_CMD="/root/GiantVM/qemu-build/x86_64-softmmu/qemu-system-x86_64 "
IMG_PATH=/root/GiantVM/guest
SHARE_PATH=/mnt/private/GVM/
mkdir -p $SHARE_PATH

# OS & DISK Image

VM_IMAGE=$IMG_PATH/os2.qcow2
DISK_IMAGE=$IMG_PATH/disk.qcow2
KERNEL=$IMG_PATH/bzImage.mod
INITRD=$IMG_PATH/ramdisk.img.mod

#######  Constant End ######

CMD=$1

function help () 
{
        echo
        echo "usage: $0 {set|delete|guest|info|list|start|stop|status|restart|force-stop|dry-run|ib_list}"
        echo
        echo "  ex) $0 set vm_name {ib_ip,...} {cpu_cnt} {mem_size} {cluster_pool} {cluster_volume} {cluster_net}"
        echo "  ex) $0 delete vm_name"
        echo "  ex) $0 guest vm_name {usage | uptime | network}"
        echo "  ex) $0 info vm_name"
        echo "  ex) $0 list"
        echo "  ex) $0 start vm_name"
        echo "  ex) $0 stop vm_name"
        echo "  ex) $0 restart vm_name"
        echo "  ex) $0 status vm_name"
        echo "  ex) $0 force-stop vm_name"
        echo "  ex) $0 dry-run vm_name"
        echo "  ex) $0 ib_list {set|get} [ib_ip,...]"
        exit 1
}

function check_vm () 
{
    VM_NAME=$1
    if [ ! -f "$SHARE_PATH/$VM_NAME" ]; then
        echo "Can't found VM_NAME : $VM_NAME"
        exit 1
    fi
}

function get_vnc_num ()
{
    VNC_LIST=()

    for vnc_num in `cd $SHARE_PATH && ls | grep -v ib_list | xargs cat | cut -d" " -f7`
    do
#        echo $vnc_num
        VNC_LIST+=($vnc_num)
    done

#    for value in "${VNC_LIST[@]}"
#    do
#        echo $value
#    done

   
    IFS=$'\n' sorted=($(sort -r <<<"${VNC_LIST[*]}"))
    local count=0
    for vnc_hit in "${VNC_LIST[@]}"
    do
        if [ "$vnc_hit" != "$count" ]; then
            echo $count
            return 0
        else
            count=`expr $count + 1`
        fi
    done
    echo $count
}

if [ "$CMD" == "set" ]; then
    [ $# -lt 7 ] && help
    VM_NAME=$2
    VM_IP=$3
    VM_CPU=$4
    VM_MEM=$5
    VM_POOL=$6
    VM_VOL=$7
    VM_NET=$8
    VM_VNC=$(get_vnc_num)

    echo "$VM_IP $VM_CPU $VM_MEM $VM_POOL $VM_VOL $VM_NET $VM_VNC" > $SHARE_PATH/$VM_NAME

    if [ $? -ne 0 ]; then
        echo "VM config error : $VM_NAME" && exit 1
    else
        exit 0
    fi
elif [ "$CMD" == "delete" ]; then
    VM_NAME=$2
    check_vm $VM_NAME
    rm -f $SHARE_PATH/$VM_NAME
    [ $? -ne 0 ] && echo "VM delete error : $VM_NAME" && exit 1
    exit 0
elif [ "$CMD" == "guest" ]; then
    VM_NAME=$2
    check_vm $VM_NAME

    vnc_num=$(cut -d" " -f7 $SHARE_PATH/$VM_NAME)
    [ $? -ne 0 ] && echo "VM guest error : $VM_NAME" && exit 1

    ssh_port=`expr 20000 + $vnc_num`
    ssh_status=$(netstat -nap | grep $ssh_port | grep sshd)
    [ "$ssh_status" == "" ] && echo "VM guest error : $VM_NAME" && exit 1

    GUEST_CMD=$3
    if [ "$GUEST_CMD" == "usage" ];then
        echo not implemented yet
    elif [ "$GUEST_CMD" == "uptime" ];then
        uptime_str=$(ssh -p $ssh_port localhost uptime)

        if  ( echo $uptime_str | grep day >/dev/null ); then
            uptime_ret=$(echo $uptime_str | cut -d" " -f3 | cut -d"," -f1)
            echo 0-${uptime_ret}:00
        elif ( echo $uptime_str | grep min  >/dev/null); then
            uptime_ret=$(echo $uptime_str | cut -d" " -f3 | cut -d"," -f1)
            echo 0-00:${uptime_ret}:00
        else
            uptime_ret=$(echo $uptime_str | cut -d" " -f3,6| cut -d"," -f1)
            echo ${uptime_ret/ /-}:00
        fi
    elif [ "$GUEST_CMD" == "network" ];then
        network_str=$(ssh -p $ssh_port localhost "ip addr | grep 'inet ' | grep -v 127 | sed -e 's/^*//g'")
        echo $(echo $network_str | cut -d' ' -f2)
    else
        help
    fi

    exit 0
elif [ "$CMD" == "info" ]; then
    VM_NAME=$2
    check_vm $VM_NAME
    cat $SHARE_PATH/$VM_NAME
    [ $? -ne 0 ] && echo "VM info error : $VM_NAME" && exit 1
    exit 0
elif [ "$CMD" == "list" ]; then
    ls $SHARE_PATH/ | grep -v ib_list
    [ $? -ne 0 ] && echo "VM list error" && exit 1
    exit 0
elif [ "$CMD" == "start" ] || [ "$CMD" == "stop" ] || [ "$CMD" == "force-stop" ] \
  || [ "$CMD" == "status" ] || [ "$CMD" == "restart" ] || [ "$CMD" == "dry-run" ]; then
    VM_NAME=$2
    check_vm $VM_NAME
    IFS=" " read -ra VM_STR <<< `cat $SHARE_PATH/$VM_NAME`
    VM_IP=${VM_STR[0]}
    VM_CPU=${VM_STR[1]}
    VM_MEM=${VM_STR[2]}
    VM_POOL=${VM_STR[3]}
    VM_VOL=${VM_STR[4]}
    VM_NET=${VM_STR[5]}
    VM_VNC=${VM_STR[6]}

elif [ "$CMD" == "stop" ]; then
    VM_NAME=$2
    check_vm $VM_NAME
elif [ "$CMD" == "status" ]; then
    VM_NAME=$2
    check_vm $VM_NAME
elif [ "$CMD" == "restart" ]; then
    VM_NAME=$2
    check_vm $VM_NAME
elif [ "$CMD" == "force-stop" ]; then
    VM_NAME=$2
    check_vm $VM_NAME
elif [ "$CMD" == "dry-run" ]; then
    VM_NAME=$2
    check_vm $VM_NAME
elif [ "$CMD" == "ib_list" ]; then
    SUB_CMD=$2
    SUB_IPLIST=$3
    if [ "$SUB_CMD" == "set" ];then
        echo $SUB_IPLIST > $SHARE_PATH/ib_list
    elif [ "$SUB_CMD" == "get" ];then
        cat $SHARE_PATH/ib_list
    else
        help
    fi
    exit 0
else
    help
fi

####### Start / Stop / Status ... ######

IP_LIST=(`echo $VM_IP | tr "," " "`)
NODE_CNT=${#IP_LIST[@]}
NODE_VCPU=$VM_CPU
MEM_SIZE=$VM_MEM
CMD_MODE=$CMD

# Memory & CPU
NUMA_RAM=$MEM_SIZE
CPU_CNT=$((NODE_VCPU  * NODE_CNT))
MEM_SIZE=$((NUMA_RAM * NODE_CNT * 1024))

# GiantVM Command Setting

if [ ! -z $KERNEL ];then
    COMMAND+="-kernel ${KERNEL} "
    COMMAND+="-initrd ${INITRD} "
    COMMAND+="-append \"text console=ttyS0 root=/dev/sda1 nokaslr transparent_hugepage=never boot_delay=$VM_VNC \" "
fi

COMMAND+="--nographic --enable-kvm -name $VM_NAME "
COMMAND+="-hda ${VM_IMAGE} -drive file=${DISK_IMAGE},cache=none,index=1 "
COMMAND+="-cpu host -machine kernel-irqchip=off "
COMMAND+="-smp ${CPU_CNT} -m ${MEM_SIZE} -serial mon:stdio "
COMMAND+="-vcpu pin-all=on "
COMMAND+="-net nic -net tap,ifname=tap0 "
# QMP ==> virtio conflict
#COMMAND+="-chardev socket,path=/tmp/qga.sock,server=on,wait=off,id=qga0 "
#COMMAND+="-device virtio-serial "
#COMMAND+="-device virtserialport,chardev=qga0,name=org.qemu.guest_agent.0 "

for id in $(seq 0 $NODE_CNT)
do
        [ $id = $NODE_CNT ] && break

        TMP=$(($id * $NODE_VCPU))-
        TMP+=$((($id+1) * $NODE_VCPU -1))
        COMMAND+="-object memory-backend-ram,size=${NUMA_RAM}G,id=ram${id} "
        COMMAND+="-numa node,nodeid=${id},cpus=${TMP},memdev=ram${id} "
done

for id in $(seq 0 $NODE_CNT)
do
        [ $id = $NODE_CNT ] && exit

        EXTRA_CMD="-local-cpu ${NODE_VCPU},start=$((id * NODE_VCPU)),iplist=\"${IP_LIST[*]}\" "
#        EXTRA_CMD+="-monitor telnet:127.0.0.1:123${id},server,nowait "
        [ $id = 0 ] && EXTRA_CMD+="-vnc :$VM_VNC "

        if [ $CMD_MODE == "start" ];then
                echo "Start logging ... $id-${IP_LIST[$id]}"
                ssh ${IP_LIST[$id]} "$NUMA_CMD 0-$((NODE_VCPU -1)) $GVM_CMD $COMMAND $EXTRA_CMD" \
                        > $id-${IP_LIST[$id]}-$VM_NAME.log 2>&1 &
                sleep 3
        elif [ $CMD_MODE == "force-stop" ] || [ $CMD_MODE == "stop" ];then
                echo "Stopping GVM-Qemu : $VM_NAME  ${IP_LIST[$id]} ..."
                ssh ${IP_LIST[$id]} "ps -ef | grep \"\-name $VM_NAME \" | grep -v numactl | grep -v grep | tr -s ' ' | cut -d ' ' -f 2 | xargs kill -9"
                continue
        elif [ $CMD_MODE == "status" ];then
                echo "Status GVM-Qemu ${IP_LIST[$id]} ..."
                ssh ${IP_LIST[$id]} "ps -ef | grep \"\-name $VM_NAME \" | grep -v numactl | grep -v grep" 
                ssh ${IP_LIST[$id]} "ps -ef | grep \"\[qemu\-system\-x86_64\]\""
                continue
        elif [ $CMD_MODE == "dry-run" ];then
                echo "GiantVM-HOST($id) on ${IP_LIST[$id]} : $NUMA_CMD 0-$((NODE_VCPU -1)) $GVM_CMD $COMMAND $EXTRA_CMD"
                continue
        else
                help
        fi
done
