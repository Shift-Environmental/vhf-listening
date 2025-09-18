import numpy as np
from gnuradio import gr
import os
import logging
import sys

# Add venv to path if needed
venv_paths = ['/home/pi/vhf-listening/venv/lib/python3.11/site-packages',
              '/home/carolyn/projects/vhf-listening/venv/lib/python3.11/site-packages',
              '/home/carolyn/projects/vhf-listening/venv/lib/python3.12/site-packages']
for venv_path in venv_paths:
    if os.path.exists(venv_path) and venv_path not in sys.path:
        sys.path.insert(0, venv_path)

try:
    import shout
    from dotenv import load_dotenv
    import lameenc
    SHOUT_AVAILABLE = True
    LAMEENC_AVAILABLE = True
except ImportError as e:
    print(f'Import error: {e}')
    SHOUT_AVAILABLE = False
    LAMEENC_AVAILABLE = False
    def load_dotenv(x): pass

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

class blk(gr.sync_block):
    def __init__(self):
        gr.sync_block.__init__(self, name="Icecast Sink", in_sig=[np.float32], out_sig=None)
        self._load_config()
        self.shout = None
        self.connected = False
        self.encoder = None
        self._setup_encoder()
        logger.info("Icecast sink initialized")
        logger.info(f"Target: {self.icecast_host}:{self.icecast_port}{self.icecast_mount}")

    def _load_config(self):
        try:
            env_path = os.path.join(os.path.dirname(__file__), '..', '.env')
            load_dotenv(env_path)
            self.icecast_host = os.getenv('ICECAST_HOST', 'localhost')
            self.icecast_port = int(os.getenv('ICECAST_PORT', '8000'))
            self.icecast_password = os.getenv('ICECAST_PASSWORD', 'hackme')
            self.icecast_mount = os.getenv('ICECAST_MOUNT', '/stream.mp3')
            self.stream_name = os.getenv('ICECAST_NAME', 'VHF Listening Station')
            self.stream_genre = os.getenv('ICECAST_GENRE', 'Radio')
            logger.info("Icecast configuration loaded")
        except Exception as e:
            logger.error(f"Config failed: {e}")
            self.icecast_host = 'localhost'
            self.icecast_port = 8000
            self.icecast_password = 'hackme'
            self.icecast_mount = '/stream.mp3'
            self.stream_name = 'VHF Listening Station'
            self.stream_genre = 'Radio'

    def _setup_encoder(self):
        if not LAMEENC_AVAILABLE:
            logger.error("lameenc not available")
            return
        try:
            self.encoder = lameenc.Encoder()
            self.encoder.set_bit_rate(128)
            self.encoder.set_in_sample_rate(48000)
            self.encoder.set_channels(1)
            self.encoder.set_quality(2)
            logger.info("MP3 encoder initialized")
        except Exception as e:
            logger.error(f"Encoder setup failed: {e}")
            self.encoder = None

    def start(self):
        logger.info("Starting Icecast sink...")
        if not SHOUT_AVAILABLE:
            logger.error("python-shout not available")
            return False
        try:
            self.shout = shout.Shout()
            self.shout.host = self.icecast_host
            self.shout.port = self.icecast_port
            self.shout.user = 'source'
            self.shout.password = self.icecast_password
            self.shout.mount = self.icecast_mount
            self.shout.format = 'mp3'
            self.shout.protocol = 'http'
            self.shout.name = self.stream_name
            self.shout.genre = self.stream_genre
            self.shout.open()
            logger.info("Connected to Icecast!")
            self.connected = True
        except Exception as e:
            logger.error(f"Connection failed: {e}")
            self.connected = False
        return True

    def stop(self):
        if self.shout and self.connected:
            try:
                self.shout.close()
            except:
                pass
        self.connected = False
        return True

    def work(self, input_items, output_items):
        if not self.connected or not self.encoder:
            return len(input_items[0])
        audio_samples = input_items[0]
        try:
            pcm_data = (audio_samples * 32767).astype(np.int16)
            mp3_data = self.encoder.encode(pcm_data)
            if mp3_data:
                self.shout.send(bytes(mp3_data))
                self.shout.sync()
        except Exception as e:
            logger.error(f"Streaming error: {e}")
            self.connected = False
        return len(audio_samples)