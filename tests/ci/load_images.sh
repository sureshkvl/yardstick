#!/bin/bash
##############################################################################
# Copyright (c) 2015 Ericsson AB, Huawei Technologies Co.,Ltd and others.
#
# All rights reserved. This program and the accompanying materials
# are made available under the terms of the Apache License, Version 2.0
# which accompanies this distribution, and is available at
# http://www.apache.org/licenses/LICENSE-2.0
##############################################################################

# Set up the environment to run yardstick test suites.

set -e

YARD_IMG_ARCH=amd64
export YARD_IMG_ARCH

if ! grep -q "Defaults env_keep += \"YARD_IMG_ARCH\"" "/etc/sudoers"; then
    sudo echo "Defaults env_keep += \"YARD_IMG_ARCH YARDSTICK_REPO_DIR\"" >> /etc/sudoers
fi

ARCH_SCRIPT="test -f /etc/fuel_openstack_arch && grep -q arm64 /etc/fuel_openstack_arch"
if [ "$INSTALLER_TYPE" == "fuel" ]; then
    sshpass -p r00tme ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -l root $INSTALLER_IP "${ARCH_SCRIPT}" && YARD_IMG_ARCH=arm64
fi

UCA_HOST="cloud-images.ubuntu.com"
if [ $YARD_IMG_ARCH = "arm64" ]; then
    export VIVID_IMG_URL="http://${UCA_HOST}/vivid/current/vivid-server-cloudimg-arm64.tar.gz"
    if ! grep -q "Defaults env_keep += \"VIVID_IMG_URL\"" "/etc/sudoers"; then
        sudo echo "Defaults env_keep += \"VIVID_IMG_URL\"" >> /etc/sudoers
    fi
fi

build_yardstick_image()
{
    echo
    echo "========== Build yardstick cloud image =========="

    if [[ "$DEPLOY_SCENARIO" == *"-lxd-"* ]]; then
        local cmd="sudo $(which yardstick-img-lxd-modify) $(pwd)/tools/ubuntu-server-cloudimg-modify.sh"

        # Build the image. Retry once if the build fails
        $cmd || $cmd

        if [ ! -f $RAW_IMAGE ]; then
            echo "Failed building RAW image"
            exit 1
        fi
    else
        local cmd="sudo $(which yardstick-img-modify) $(pwd)/tools/ubuntu-server-cloudimg-modify.sh"

        # Build the image. Retry once if the build fails
        $cmd || $cmd

        if [ ! -f $QCOW_IMAGE ]; then
            echo "Failed building QCOW image"
            exit 1
        fi
    fi
}

load_yardstick_image()
{
    echo
    echo "========== Loading yardstick cloud image =========="
    EXTRA_PARAMS=""
    if [ $YARD_IMG_ARCH = "arm64" ]; then
        VIVID_IMAGE="/tmp/vivid-server-cloudimg-arm64.tar.gz"
        VIVID_KERNEL="/tmp/vivid-server-cloudimg-arm64-vmlinuz-generic"
        cd /tmp
        if [ ! -f $VIVID_IMAGE ]; then
            wget $VIVID_IMG_URL
        fi
        if [ ! -f $VIVID_KERNEL ]; then
            tar zxf $VIVID_IMAGE $(basename $VIVID_KERNEL)
        fi
        create_vivid_kernel=$(openstack image create \
                --public \
                --disk-format qcow2 \
                --container-format bare \
                --file $VIVID_KERNEL \
                yardstick-vivid-kernel)

        GLANCE_KERNEL_ID=$(echo "$create_vivid_kernel" | grep " id " | awk '{print $(NF-1)}')
        if [ -z "$GLANCE_KERNEL_ID" ]; then
            echo 'Failed uploading kernel to cloud'.
            exit 1
        fi

        command_line="root=/dev/vdb1 console=tty0 console=ttyS0 console=ttyAMA0 rw"

        EXTRA_PARAMS="--property kernel_id=$GLANCE_KERNEL_ID --property os_command_line=\"$command_line\""

        rm -f $VIVID_KERNEL $VIVID_IMAGE
        cd $YARDSTICK_REPO_DIR
    fi

    # VPP requires guest memory to be backed by large pages
    if [[ "$DEPLOY_SCENARIO" == *"-fdio-"* ]]; then
        EXTRA_PARAMS=$EXTRA_PARAMS" --property hw_mem_page_size=large"
    fi

    if [[ "$DEPLOY_SCENARIO" == *"-lxd-"* ]]; then
        output=$(eval openstack image create \
            --public \
            --disk-format root-tar \
            --container-format bare \
            $EXTRA_PARAMS \
            --file $RAW_IMAGE \
            yardstick-image)
    else
        output=$(eval openstack image create \
            --public \
            --disk-format qcow2 \
            --container-format bare \
            $EXTRA_PARAMS \
            --file $QCOW_IMAGE \
            yardstick-image)
    fi

    echo "$output"

    GLANCE_IMAGE_ID=$(echo "$output" | grep " id " | awk '{print $(NF-1)}')

    if [ -z "$GLANCE_IMAGE_ID" ]; then
        echo 'Failed uploading image to cloud'.
        exit 1
    fi

    if [ "$DEPLOY_SCENARIO" == *"-lxd-"* ]; then
        sudo rm -f $RAW_IMAGE
    else
        sudo rm -f $QCOW_IMAGE
    fi

    echo "Glance image id: $GLANCE_IMAGE_ID"
}

load_cirros_image()
{
    echo
    echo "========== Loading cirros cloud image =========="

    local image_file=/home/opnfv/images/cirros-0.3.3-x86_64-disk.img

    EXTRA_PARAMS=""
    # VPP requires guest memory to be backed by large pages
    if [[ "$DEPLOY_SCENARIO" == *"-fdio-"* ]]; then
        EXTRA_PARAMS=$EXTRA_PARAMS" --property hw_mem_page_size=large"
    fi

    output=$(openstack image create \
        --disk-format qcow2 \
        --container-format bare \
        $EXTRA_PARAMS \
        --file $image_file \
        cirros-0.3.3)
    echo "$output"

    CIRROS_IMAGE_ID=$(echo "$output" | grep " id " | awk '{print $(NF-1)}')
    if [ -z "$CIRROS_IMAGE_ID" ]; then
        echo 'Failed uploading cirros image to cloud'.
        exit 1
    fi

    echo "Cirros image id: $CIRROS_IMAGE_ID"
}

load_ubuntu_image()
{
    echo
    echo "========== Loading ubuntu cloud image =========="

    local ubuntu_image_file=/home/opnfv/images/trusty-server-cloudimg-amd64-disk1.img

    EXTRA_PARAMS=""
    # VPP requires guest memory to be backed by large pages
    if [[ "$DEPLOY_SCENARIO" == *"-fdio-"* ]]; then
        EXTRA_PARAMS=$EXTRA_PARAMS" --property hw_mem_page_size=large"
    fi

    output=$(openstack image create \
        --disk-format qcow2 \
        --container-format bare \
        $EXTRA_PARAMS \
        --file $ubuntu_image_file \
        Ubuntu-14.04)
    echo "$output"

    UBUNTU_IMAGE_ID=$(echo "$output" | grep " id " | awk '{print $(NF-1)}')

    if [ -z "$UBUNTU_IMAGE_ID" ]; then
        echo 'Failed uploading UBUNTU image to cloud'.
        exit 1
    fi

    echo "Ubuntu image id: $UBUNTU_IMAGE_ID"
}

create_nova_flavor()
{
    if ! openstack flavor list | grep -q yardstick-flavor; then
        echo
        echo "========== Create nova flavor =========="
        # Create the nova flavor used by some sample test cases
        openstack flavor create --id 100 --ram 512 --disk 3 --vcpus 1 yardstick-flavor
        # DPDK-enabled OVS requires guest memory to be backed by large pages
        if [[ "$DEPLOY_SCENARIO" == *"-ovs-"* ]]; then
            openstack flavor set --property hw:mem_page_size=large yardstick-flavor
        fi
        # VPP requires guest memory to be backed by large pages
        if [[ "$DEPLOY_SCENARIO" == *"-fdio-"* ]]; then
            openstack flavor set --property hw:mem_page_size=large yardstick-flavor
        fi
    fi
}

main()
{
    QCOW_IMAGE="/tmp/workspace/yardstick/yardstick-image.img"
    RAW_IMAGE="/tmp/workspace/yardstick/yardstick-image.tar.gz"

    build_yardstick_image
    load_yardstick_image
    if [ $YARD_IMG_ARCH = "arm64" ]; then
        sed -i 's/image: cirros-0.3.3/image: TestVM/g' tests/opnfv/test_cases/opnfv_yardstick_tc002.yaml \
        samples/ping.yaml
        #We have overlapping IP with the real network
        for filename in tests/opnfv/test_cases/*; do
            sed -i "s/cidr: '10.0.1.0\/24'/cidr: '10.3.1.0\/24'/g" $filename
        done
    else
        load_cirros_image
        load_ubuntu_image
    fi
    create_nova_flavor
}

main