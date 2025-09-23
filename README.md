### Useful commands

#### FFMPEG Test Scripts (Make sure to modify the SOURCE_PASS)

```sh
ffmpeg -f lavfi -i "sine=frequency=1000" -acodec mp3 -ab 128k -f mp3 -content_type audio/mpeg icecast://source:SOURCE_PASS@vhf.shiftcims.com:8888/test
```

```sh
ffmpeg -f lavfi -i "sine=frequency=1000" -acodec libopus -ab 128k -f ogg -content_type application/ogg icecast://source:SOURCE_PASS@vhf.shiftcims.com:8888/test.opus
```
