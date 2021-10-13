#!/bin/bash                                                                                                                                                                                                                                   
                                                                                                                                                                                                                                              
#######  Constant Setting ######                                                                                                                                                                                                              
                                                                                                                                                                                                                                              
GVM_CMD="/root/ETRI/build/x86_64-softmmu/qemu-system-x86_64 "   
IP_LIST=(100.0.0.100 100.0.0.101)                                                                                                                                                                                                     [50/347]
IMG_PATH=/root/image/guest                                                                                                                                                                                                                    
#NUMA_CMD="taskset -c"                                                                                                                                                                                                                        
NUMA_CMD="numactl -C"                                                                                                                                                                                                                         
                                                                                                                                                                                                                                              
# OS & DISK Image                                                                                                                                                                                                                             
                                                                                                                                                                                                                                              
VM_IMAGE=$IMG_PATH/ubuntu-server2.img                                                                                                                                                                                                         
DISK_IMG=/mnt/giant-vol/test.img                                                                                                                                                                                                              
#DISK_IMG=/dev/centos00/home                                                                                                                                                                                                                  
KERNEL=$IMG_PATH/bzImage.mod                                                                                                                                                                                                                  
INITRD=$IMG_PATH/ramdisk.img.mod                                                                                                                                                                                                              
                                                                                                                                                                                                                                              
#######  Constant End ######                                                                                                                                                                                                                  
                                                                                                                                                                                                                                              
                                                                                                                                                                                                                                              
NODE_CNT=$1                                                                                                                                                                                                                                   
NODE_VCPU=$2                                                                                                                                                                                                                                  
MEM_SIZE=$3                                                                                                                                                                                                                                   
CMD_MODE=$4                                                                                                                                                                                                                                   
                                                                                                                                                                                                                                              
if [ "$NODE_CNT" == "" ] ||  [ "$NODE_VCPU" == "" ] || \                                                                                                                                                                                      
                [ "$MEM_SIZE" == "" ]; then                                                                                                                                                                                                   
        echo                                                                                                                                                                                                                                  
        echo "usage: $0 {NODE_CNT} {NODE_VCPU} {MEM_SIZE} [CMD_MODE]"                                                                                                                                                                         
        echo                                                                                                                                                                                                                                  
        echo "          NODE_CNT  : total giant host count"                                                                                                                                                                                   
        echo "          NODE_VCPU : local cpu count"                                                                                                                                                                                          
        echo "          MEM_SIZE  : local memory size"                                                                                                                                                                                        
        echo "          CMD_MODE  : kill | start | status"                                                                                                                                                                                    
        echo                                                                                                                                                                                                                                  
        echo "        * HOST LIST : ${IP_LIST[*]}"                                                                                                                                                                                            
        echo "        * GVM IMAGE : $VM_IMAGE"                                                                                                                                                                                                
        echo "        * DISK IMG  : $DISK_IMG"                                                                                                                                                                                                
        echo "        * KERNEL    : $KERNEL"                                                                                                                                                                                                  
        echo "        * INITRD    : $INITRD"                                                                                                                                                                                                  
                                                                                                                                                                                                                                              
        exit 1                                                                                                                                                                                                                                
fi                                                                                                                                                                                                                                            
                                                                                                                                                                                                                                              
# Memory & CPU                                                                                                                                                                                                                                
                                                                                                                                                                                                                                              
NUMA_RAM=$MEM_SIZE                                                                                                                                                                                                                            
CPU_CNT=$((NODE_VCPU  * NODE_CNT))                                                                                                                                                                                                            
MEM_SIZE=$((NUMA_RAM * NODE_CNT * 1024))                                                                                                                                                                                                      
                                                                                                                                                                                                                                              
# GiantVM Command Setting                                                                                                                                                                                                                     
                                                                                                                                                                                                                                              
if [ ! -z $KERNEL ];then                                                                                                                                                                                                                      
        COMMAND+="-kernel ${KERNEL} "                                                                                                                                                                                                         
        COMMAND+="-initrd ${INITRD} "                                                                                                                                                                                                         
        COMMAND+="-append \"text console=ttyS0 root=/dev/sda1 nokaslr transparent_hugepage=never \" "
fi


COMMAND+="--nographic --enable-kvm "
#COMMAND+="-hda ${VM_IMAGE} -hdb ${DISK_IMG} "
COMMAND+="-hda ${VM_IMAGE} -drive file=${DISK_IMG},cache=none,index=1 "
COMMAND+="-cpu host -machine kernel-irqchip=off "
COMMAND+="-smp ${CPU_CNT} -m ${MEM_SIZE} -serial mon:stdio "
COMMAND+="-monitor telnet:127.0.0.1:1234,server,nowait -vnc :0 "
COMMAND+="-vcpu pin-all=on "

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
        echo 

        if [ $id = $NODE_CNT ];then
                exit
        fi

        if [ ! -z $CMD_MODE ] && [ $CMD_MODE == "stop" ];then
                echo "Stopping GVM-Qemu ${IP_LIST[$id]} ..."
                ssh ${IP_LIST[$id]} "killall -9 $GVM_CMD" 
                continue
        fi
        if [ ! -z $CMD_MODE ] && [ $CMD_MODE == "status" ];then
                echo "Status GVM-Qemu ${IP_LIST[$id]} ..."
                ssh ${IP_LIST[$id]} "ps -ef | grep $GVM_CMD | grep -v numactl | grep -v grep" 
                ps -ef | grep qemu | grep -v grep
                netstat -nap | grep 1234
                continue
        fi

        EXTRA_CMD="-local-cpu ${NODE_VCPU},start=$((id * NODE_VCPU)),iplist=\"${IP_LIST[*]}\" "
        echo "GiantVM-HOST($id) on ${IP_LIST[$id]} : $NUMA_CMD 0-$((NODE_VCPU -1)) $GVM_CMD $COMMAND $EXTRA_CMD"

        if [ ! -z $CMD_MODE ] && [ $CMD_MODE == "start" ];then

                echo "Start logging ... $id-${IP_LIST[$id]}"
                ssh ${IP_LIST[$id]} "$NUMA_CMD 0-$((NODE_VCPU -1)) $GVM_CMD $COMMAND $EXTRA_CMD" \
                        > $id-${IP_LIST[$id]}.log 2>&1 &
                sleep 3
        fi
done
