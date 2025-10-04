#!/bin/bash

magick '/Users/v/Pictures/Gallery/film/sept-30-25/_1116193-Edit.jpg' \
    -resize '1374x1844' \
    -bordercolor black \
    -border 3 \
    -background white \
    -gravity center \
    -extent '1440x1920' \
    -quality 92 '/Users/v/Pictures/Gallery/film/sept-30-25/_1116193-Edit__processed.jpg'\
&&
magick '/Users/v/Pictures/Gallery/film/sept-30-25/_1116193-Edit.jpg' \
    -gravity east -crop '50x100%+0+0' \
    -resize '1440x1920' \
    -quality 92 '/Users/v/Pictures/Gallery/film/sept-30-25/_1116193-Edit-r.jpg' \
&& 
magick '/Users/v/Pictures/Gallery/film/sept-30-25/_1116193-Edit.jpg' \
    -gravity west -crop '50x100%+0+0' \
    -resize '1440x1920' \
    -quality 92 '/Users/v/Pictures/Gallery/film/sept-30-25/_1116193-Edit-l.jpg'

