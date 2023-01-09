#!/bin/bash
set -e

function init_variables() {
    print_help_if_needed $@
    script_dir=$(dirname $(realpath "$0"))
    source $script_dir/../../../../scripts/misc/checks_before_run.sh

    readonly POSTPROCESS_DIR="$TAPPAS_WORKSPACE/apps/gstreamer/libs/post_processes"
    readonly DEFAULT_VIDEO_SOURCE="$TAPPAS_WORKSPACE/apps/gstreamer/raspberrypi/multinetworks_parallel/resources/instance_segmentation.mp4"
    readonly DEFAULT_HEF_PATH="$TAPPAS_WORKSPACE/apps/gstreamer/raspberrypi/multinetworks_parallel/resources/joined_fast_depth_ssd_mobilenet_v1_no_alls.hef"
    readonly DEFAULT_VDEVICE_KEY="1"

    input_source=$DEFAULT_VIDEO_SOURCE
    hef_path=$DEFAULT_HEF_PATH
    depth_estimation_post_so="$POSTPROCESS_DIR/libdepth_estimation.so"
    detection_post_so="$POSTPROCESS_DIR/libmobilenet_ssd_post.so"

    depth_estimation_net_name="joined_fast_depth_ssd_mobilenet_v1_no_alls/fast_depth"
    detection_net_name="joined_fast_depth_ssd_mobilenet_v1_no_alls/ssd_mobilenet_v1_no_alls"

    print_gst_launch_only=false
    additonal_parameters=""
    camera_input_width=416
    camera_input_height=416
    camera_framerate="40/1"
    camera_input_format="RGB"
}

function print_usage() {
    echo "Detection and Depth estimation pipeline usage:"
    echo ""
    echo "Options:"
    echo "  --help                  Show this help"
    echo "  -i INPUT --input INPUT  Set the input video file path (default $input_source)"
    echo "  --show-fps              Print fps"
    echo "  --print-gst-launch      Print the ready gst-launch command without running it"
    exit 0
}

function validate_rpi_platform_camera_support() {
    os_id=$(cat /etc/os-release | grep ^ID=)
    if [ "$os_id" != "ID=debian" ]; then
        echo "Camera device supported only in Debian release of Raspberry PI"
        exit 1
    fi

    identify_v4l=$(gst-launch-1.0 v4l2src device=$input_source num-buffers=1 ! fakesink 2>&1 | grep 'Cannot identify device' | wc -l)
    if [ "$identify_v4l" -eq 1 ]; then
        echo "Cannot identify v4l device '$input_source'"
        exit 1
    fi

    num_of_cam_devices_sup=$(gst-launch-1.0 --gst-debug=v4l2src:5 v4l2src device=$input_source num-buffers=1 ! fakesink 2>&1 | sed -une '/caps of src/ s/[:;] /\n/gp' | grep $camera_input_format | wc -l)
    if [ "$num_of_cam_devices_sup" -eq 0 ]; then
        echo "v4l device '$input_source' is not supporting requested input format '$camera_input_format'"
        exit 1
    fi
}

function print_help_if_needed() {
    while test $# -gt 0; do
        if [ "$1" = "--help" ] || [ "$1" == "-h" ]; then
            print_usage
        fi

        shift
    done
}

function parse_args() {
    while test $# -gt 0; do
        if [ "$1" = "--show-fps" ]; then
            echo "Printing fps"
            additonal_parameters="-v | grep hailo_display"
        elif [ "$1" = "--print-gst-launch" ]; then
            print_gst_launch_only=true
        elif [ "$1" = "--input" ] || [ "$1" == "-i" ]; then
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

# If the video provided is from a camera
if [[ $input_source =~ "/dev/video" ]]; then
    validate_rpi_platform_camera_support
    source_element="v4l2src device=$input_source name=src_0 !  video/x-raw, format=$camera_input_format, width=$camera_input_width, height=$camera_input_height, framerate=$camera_framerate, pixel-aspect-ratio=1/1 ! \
                    queue max-size-buffers=5 max-size-bytes=0 max-size-time=0 ! \
                    videoflip video-direction=horiz"
else
    source_element="filesrc location=$input_source name=src_0 ! qtdemux ! h264parse ! \
                    queue leaky=no max-size-buffers=10 max-size-bytes=0 max-size-time=0 ! \
                    avdec_h264 ! \
                    queue leaky=no max-size-buffers=10 max-size-bytes=0 max-size-time=0 ! \
                    videoconvert n-threads=4"
    sync_pipeline=true
fi

PIPELINE="gst-launch-1.0 \
    $source_element ! \
    queue leaky=no max-size-buffers=10 max-size-bytes=0 max-size-time=0 ! \
    tee name=t ! \
    aspectratiocrop aspect-ratio=1/1 ! \
    queue ! videoscale n-threads=2 ! \
    queue leaky=no max-size-buffers=10 max-size-bytes=0 max-size-time=0 ! \
    hailonet hef-path=$hef_path is-active=true scheduling-algorithm=0 \
    vdevice-key=$DEFAULT_VDEVICE_KEY net-name=$depth_estimation_net_name ! \
    queue leaky=no max-size-buffers=10 max-size-bytes=0 max-size-time=0 ! \
    hailofilter so-path=$depth_estimation_post_so qos=false ! videoconvert ! \
    queue leaky=no max-size-buffers=10 max-size-bytes=0 max-size-time=0 ! \
    hailooverlay qos=false ! \
    queue leaky=no max-size-buffers=10 max-size-bytes=0 max-size-time=0 ! \
    videoconvert ! \
    queue leaky=no max-size-buffers=10 max-size-bytes=0 max-size-time=0 ! \
    fpsdisplaysink video-sink=ximagesink name=hailo_display sync=false text-overlay=false \
    t. ! \
    videoscale n-threads=2 ! \
    queue leaky=no max-size-buffers=10 max-size-bytes=0 max-size-time=0 ! \
    hailonet hef-path=$hef_path is-active=true scheduling-algorithm=0 \
    vdevice-key=$DEFAULT_VDEVICE_KEY net-name=$detection_net_name ! \
    queue leaky=no max-size-buffers=10 max-size-bytes=0 max-size-time=0 ! \
    hailofilter so-path=$detection_post_so function-name=mobilenet_ssd_merged qos=false ! \
    queue leaky=no max-size-buffers=10 max-size-bytes=0 max-size-time=0 ! \
    hailooverlay ! \
    queue leaky=no max-size-buffers=10 max-size-bytes=0 max-size-time=0 ! \
    videoconvert ! \
    fpsdisplaysink video-sink=ximagesink name=hailo_display2 sync=false text-overlay=false ${additonal_parameters} "

echo "Running"
echo ${PIPELINE}

if [ "$print_gst_launch_only" = true ]; then
    exit 0
fi

eval ${PIPELINE}
