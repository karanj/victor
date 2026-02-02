#!/bin/bash

# iterate over the svg files fed into on the command line
for svgfile in "$@"
do
	filename=$(basename -- "$svgfile")
	ext="${filename##*.}"
	name="${filename%.*}"

	echo "Processing $name ..."
	set -e
	mkdir "$name.iconset"

	# run inkscape from the command line to generate the iconset formatted for icns
	inkscape --export-filename="$PWD/$name.iconset/icon_16x16.png"      --export-width=16 "$PWD/$svgfile"
	inkscape --export-filename="$PWD/$name.iconset/icon_16x16@2x.png"   --export-width=32 "$PWD/$svgfile"
	inkscape --export-filename="$PWD/$name.iconset/icon_32x32.png"      --export-width=32 "$PWD/$svgfile"
	inkscape --export-filename="$PWD/$name.iconset/icon_32x32@2x.png"   --export-width=64 "$PWD/$svgfile"
	inkscape --export-filename="$PWD/$name.iconset/icon_128x128.png"    --export-width=128 "$PWD/$svgfile"
	inkscape --export-filename="$PWD/$name.iconset/icon_128x128@2x.png" --export-width=256 "$PWD/$svgfile"
	inkscape --export-filename="$PWD/$name.iconset/icon_256x256.png"    --export-width=256 "$PWD/$svgfile"
	inkscape --export-filename="$PWD/$name.iconset/icon_256x256@2x.png" --export-width=512 "$PWD/$svgfile"
	inkscape --export-filename="$PWD/$name.iconset/icon_512x512.png"    --export-width=512 "$PWD/$svgfile"
	inkscape --export-filename="$PWD/$name.iconset/icon_512x512@2x.png" --export-width=1024 "$PWD/$svgfile"

	# run osx iconutil app to convert the iconset to icns format
	iconutil -c icns "$name.iconset"

	#cleanup
	#rm -R "$name.iconset"
done
echo "Done."