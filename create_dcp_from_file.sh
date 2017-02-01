#!/bin/bash -e

OPENDCP_J2K=`pwd`/opendcp/Build/cli/opendcp_j2k
OPENDCP_MXF=`pwd`/opendcp/Build/cli/opendcp_mxf
OPENDCP_XML=`pwd`/opendcp/Build/cli/opendcp_xml
SRTTOSMPTE=`pwd`/srt2smpte/srt2smpte.sh

TITLE=$1
if [[ "$TITLE" =~ .*\..* ]]
then
    echo "First operand should be a title"
    exit 1
fi
shift

DIR=dcp_$TITLE
mkdir $DIR
cd $DIR

FILES=$@
REELS=""
REEL_NUMBER=1

for file in $FILES
do
    #ffmpeg -r 25 -i $file -r 25 -an -profile:v 3 \
    #      -cinema_mode 1  -format 0 -numresolution 6  -compression_level 30 -prog_order 4 \
    #      -pix_fmt:v xyz12be -threads 8 ./j2c/%06d.j2c
          #-pix_fmt:v gbrp12\
 
    FILENAME="${file%.*}"
    mkdir tiff j2c
    #strip out the video
    ffmpeg -i ../$file -an -threads 8 -r 24 -pix_fmt rgb24 -c:v tiff -vf "scale=1920:1080" ./tiff/%06d.tiff
    $OPENDCP_J2K -i tiff -o j2c -r 24 --threads 1 -p cinema2k --resize
    #strip out the audio
    ffmpeg -i ../$file -ar 48000 -vn tmp_audio.wav
    $OPENDCP_MXF -i j2c -o video_$FILENAME.mxf --ns smpte
    $OPENDCP_MXF -i tmp_audio.wav -o audio_$FILENAME.mxf --ns smpte
    rm tmp_audio.wav
    #strip out the subtitles
    #ffmpeg -i ../$file -map 0:s:0? tmp_subtitles.srt
    if ffmpeg -i ../$file -map 0:s:0 tmp_subtitles.srt #if there are any subtitles, then convert them to smpte format
    then
        cat tmp_subtitles.srt | $SRTTOSMPTE $TITLE $FILENAME $REEL_NUMBER > subtitles_$FILENAME.xml
        $OPENDCP_MXF -i subtitles_$FILENAME.xml -o subtitles_$FILENAME.mxf --ns smpte
    fi

    #set them all to be combined in the next step
    if [ -e subtitles_$FILENAME.mxf ]
    then
        REELS="$REELS --reel video_$FILENAME.mxf audio_$FILENAME.mxf subtitles_$FILENAME.mxf "
    else
        REELS="$REELS --reel video_$FILENAME.mxf audio_$FILENAME.mxf "
    fi
    REEL_NUMBER=$(($REEL_NUMBER + 1))
    rm -rf j2c tiff
done

echo $REELS
if [ ! -z "$REELS" ]
then
    $OPENDCP_XML $REELS --title $TITLE --kind test
else
    echo "Error: No reels specified"
    exit 2
fi
