#!/bin/bash
set -e

CURRENT_DIR="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"

function init_variables() {
    readonly RESOURCES_DIR="${CURRENT_DIR}/resources"
    readonly POSTPROCESS_DIR="/usr/lib/hailo-post-processes"
    readonly DEFAULT_POSTPROCESS_SO="$POSTPROCESS_DIR/libyolo_post.so"
    readonly DEFAULT_NETWORK_NAME="yolov5"
    readonly DEFAULT_VIDEO_SOURCE="/dev/video0"
    readonly DEFAULT_HEF_PATH="${RESOURCES_DIR}/${DEFAULT_NETWORK_NAME}m_yuv.hef"
    readonly DEFAULT_JSON_CONFIG_PATH="$RESOURCES_DIR/configs/yolov5.json" 

    postprocess_so=$DEFAULT_POSTPROCESS_SO
    network_name=$DEFAULT_NETWORK_NAME
    input_source=$DEFAULT_VIDEO_SOURCE
    hef_path=$DEFAULT_HEF_PATH
    json_config_path=$DEFAULT_JSON_CONFIG_PATH 

    print_gst_launch_only=false
    additonal_parameters=""
}

function print_usage() {
    echo "H4Z Detection pipeline usage:"
    echo ""
    echo "Options:"
    echo "  --help              Show this help"
    echo "  -i INPUT --input INPUT          Set the video source (default $input_source)"
    echo "  --show-fps          Print fps"
    echo "  --print-gst-launch  Print the ready gst-launch command without running it"
    exit 0
}

function parse_args() {
    while test $# -gt 0; do
        if [ "$1" = "--help" ] || [ "$1" == "-h" ]; then
            print_usage
            exit 0
        elif [ "$1" = "--print-gst-launch" ]; then
            print_gst_launch_only=true
        elif [ "$1" = "--show-fps" ]; then
            echo "Printing fps"
            additonal_parameters="-v 2>&1 | grep hailo_display"
        elif [ "$1" = "--input" ] || [ "$1" = "-i" ]; then
            input_source="$2"
            shift
        else
            echo "Received invalid argument: $1. See expected arguments below:"
            print_usage
            exit 1
        fi

        shift
    done
}

init_variables $@

parse_args $@

PIPELINE="gst-launch-1.0 \
    v4l2src device=$input_source name=src_0 \
	! decodebin \
    ! videoflip video-direction=horiz \
	! videoconvert qos=false n-threads=4 \
	! queue \
	! tee name=t hailomuxer name=hmux t. \
	! queue leaky=no max-size-buffers=3 max-size-bytes=0 max-size-time=0 \
	! hmux. t. \
	! videoscale qos=false n-threads=3 \
	! queue leaky=no max-size-buffers=3 max-size-bytes=0 max-size-time=0 \
	! hailonet hef-path=/home/root/apps/detection/resources/yolov5m_yuv.hef is-active=true vdevice-key=1 \
	! queue leaky=no max-size-buffers=3 max-size-bytes=0 max-size-time=0 \
	! hailofilter function-name=yolov5 config-path=/home/root/apps/detection/resources/configs/yolov5.json so-path=/usr/lib/hailo-post-processes/libyolo_post.so qos=false \
	! queue leaky=no max-size-buffers=3 max-size-bytes=0 max-size-time=0 \
	! hmux. hmux. \
	! queue leaky=no max-size-buffers=3 max-size-bytes=0 max-size-time=0 \
	! hailooverlay qos=false \
	! queue leaky=no max-size-buffers=3 max-size-bytes=0 max-size-time=0 \
	! videoconvert \
	! kmssink bus-id=fd4a0000.display fullscreen-overlay=1"

echo "Running $network_name"
echo ${PIPELINE}

if [ "$print_gst_launch_only" = true ]; then
    exit 0
fi

eval ${PIPELINE}
