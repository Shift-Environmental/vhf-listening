# GNU Radio Companion Development Guide

## Understanding GNU Radio Companion

### What is GNU Radio Companion?

**GNU Radio Companion (GRC)** is a visual programming environment for software-defined radio. Instead of writing complex signal processing code by hand, you drag and drop **blocks** (like filters, demodulators, and sources) and connect them with **wires** to create a **flowgraph**.

**Why Use GNU Radio?**
- ✅ **Professional DSP**: Industry-standard digital signal processing  
- ✅ **Visual Development**: See your signal processing pipeline clearly
- ✅ **Real-time Tuning**: Adjust parameters while listening to live audio
- ✅ **Production Ready**: Generates optimized Python code for deployment
- ✅ **Proven Reliable**: Used by researchers, engineers, and radio professionals worldwide

### Frequency Planning

**For Testing and Development:**
- Use Victoria Weather Station: 162.400 MHz
- Continuous reports make it perfect for testing

**For Production Deployment:**
- Marine Channel 16: 156.800 MHz (international emergency frequency)

### How to Change Frequency

**Quick Method (Variables Tab):**
1. Open GNU Radio Companion: `gnuradio-companion gnuradio/vhfListeningGRC.grc`
2. In a **Variable** block on the left of the screen, find the `freq` variable
3. Double-click the `freq` variable block
4. Change the **Value** field:
   - **Testing**: `162.400e6` (Victoria Weather Station)
   - **Production**: `156.800e6` (Marine Channel 16)
5. Click "Generate" to update the Python files

**Alternative (GUI Mode):**
- If in GUI mode, you can also use the frequency slider control during runtime testing
- Use this to find the optimal frequency for your location before setting the fixed value  

### GUI vs Headless Modes

**The flowgraph supports two modes:**
Test with GUI mode first to find the best settings for your antenna/location, then switch to headless mode with those optimized values.

#### 🖥️ **Development Mode (GUI Enabled)**
- Visual monitoring: See frequency spectrum and audio waveforms
- Real-time controls: Adjust frequency, gain, and filters with sliders
- Parameter tuning: Find optimal settings for your location

#### 🔧 **Production Mode (Headless)**  
- No GUI windows: Runs on headless servers (Raspberry Pi)
- Automated operation: Uses fixed parameters from development testing

### Switching Between Modes

**To Enable Development GUI:**
1. Right-click disabled blocks (QT GUI Frequency Sink, QT GUI Time Sink, QT GUI Range controls)
2. Select "Enable" - blocks change from red to normal colors
3. Right-click static Variable blocks (frequency, rf_gain, volume variables)  
4. Select "Disable" - these provide fixed values, GUI controls provide dynamic values
5. Set Options → Generate Options to "QT GUI"
6. Generate and Execute (Press "Play" button with hover text "Execute the Flow Graph") - GUI windows appear with live controls

**To Return to Production Mode:**
1. Right-click GUI blocks (QT GUI Frequency Sink, Time Sink, Range controls)
2. Select "Disable" - blocks turn red (will be ignored)
3. Right-click Variable blocks (frequency, rf_gain, volume)
4. Select "Enable" - these now provide the fixed values  
5. Update Variable values with optimal settings found during GUI testing
6. Set Options → Generate Options to "No GUI"
7. Generate (Press icon of box hovering over down arrow) - creates headless Python script (options_0.py)

*Optionally, for development you can disable the "Custom Icecast Sink" and enable the "Audio Sink" for local audio playback through speakers/headphones.*

---

## Understanding the Flowgraph

**Current Signal Chain:**
```
RTL-SDR Source → Rational Resampler → NBFM Receive → AGC2 → High Pass Filter → Low Pass Filter → Custom Icecast Sink
```

This professional signal processing chain converts raw radio waves into clean audio suitable for emergency monitoring.

**Key Blocks and Settings:**

*For detailed parameter values and tuning options, see the [Variable Reference Guide](#variable-reference-guide) at the end of this document.*

## Required Core Blocks

These blocks are essential for basic VHF reception and cannot be bypassed:

### 1. **Soapy RTLSDR Source** *(Required)*
- Purpose: Captures raw radio frequency data from antenna
- Sample Rate: `samp_rate` variable
- Center Frequency: `frequency` variable
- RF Gain: `rf_gain` variable (AGC overrides this)
- AGC: True - enables automatic gain control in RTL-SDR hardware

### 2. **Rational Resampler** *(Required)*  
- Purpose: Reduces sample rate to manageable level for demodulation
- Interpolation: `resamp_interp` variable - auto-calculated
- Decimation: `resamp_decim` variable - auto-calculated

### 3. **NBFM Receive** *(Required)*
- Purpose: Demodulates FM signal into audio
- Audio Rate: `audio_rate` variable - fixed at 48000 Hz
- Quadrature Rate: `quad_rate` variable - auto-calculated
- Max Deviation: variable - fixed at 5000 Hz - narrow band FM standard for weather/marine
- Tau: variable - fixed at 75e-6 seconds - North American de-emphasis time constant  

### 4. **Custom Icecast Sink** *(Required for Production)*
- Purpose: Streams audio directly to Icecast server with real-time MP3 encoding
- Input: Float32 audio samples from GNU Radio processing chain
- Features: MP3 encoding, Icecast connection management, environment configuration
- Implementation: Custom embedded Python block (see [Custom Icecast Sink Development](#custom-icecast-sink-development))

### 4b. **Audio Sink** *(Alternative for Development)*
- Purpose: Plays audio directly through local speakers/headphones
- Sample Rate: `audio_rate` variable - must match flowgraph audio rate (48000 Hz)
- When to use: For development, testing, and parameter tuning
- Setup: Enable this block and disable the Custom Icecast Sink for local audio monitoring

## Optional Processing Blocks

These blocks may improve signal quality but can be bypassed if they don't help in your specific setup:

### 5. **AGC2** 
- Purpose: Smooths volume variations and prevents sudden level changes
- When to enable: If audio has inconsistent volume or crackling from gain variations
- Attack Rate: `agc_rate` variable - How fast AGC responds to sudden volume increases; gentle rate prevents artifacts
- Decay Rate: `agc_rate` variable - How fast AGC responds to volume decreases; matches attack rate for symmetrical behavior
- Reference: `agc_reference` variable - Target output level AGC tries to maintain; lower values leave more headroom
- Gain: `agc_gain` variable - Initial gain multiplier before AGC takes over; usually left at 1.0 

### 6. **High Pass Filter**
- Purpose: Removes low-frequency noise, power line hum, and rumble
- When to enable: If you hear low-frequency noise or "thumping" sounds
- Decimation: 1 - No sample rate reduction; keeps the same 48kHz throughout the filter
- Gain: 1 - Unity gain means no amplification, just filtering
- Sample Rate: `audio_rate` variable - Must match the incoming audio rate (48kHz) for correct frequency calculations
- Cutoff Frequency: `highpass_cutoff_freq` variable - Frequencies below this point get filtered out
- Transition Width: `highpass_trans_width` variable - 100 Hz - How gradual the filter cutoff is; gentle rolloff to avoid artifacts
- Window: Kaiser - Mathematical method for filter design with excellent sharpness/ripple control
- Beta: default 6.76 - Controls Kaiser window shape; 6.76 is optimal compromise for audio applications

### 7. **Low Pass Filter**
- Purpose: Removes high-frequency static and hiss above voice range  
- When to enable: If you hear high-frequency static or "hissing" noise
- Decimation: 1 - No sample rate reduction; keeps the same 48kHz throughout the filter
- Gain: 1 - Unity gain means no amplification, just filtering
- Sample Rate: `audio_rate` variable - Must match the incoming audio rate (48kHz) for correct frequency calculations
- Cutoff Frequency: `lowpass_cutoff_freq` variable - Frequencies above this point get filtered out; preserves voice below
- Transition Width: `lowpass_trans_width` variable - How gradual the filter cutoff is; gentle rolloff to avoid artifacts
- Window: Kaiser - Mathematical method for filter design with optimal balance of sharpness and noise rejection
- Beta: default 6.76 - Controls Kaiser window shape; 6.76 is optimal compromise for audio applications

### 8. **Rail (Hard Limiter)**
- Purpose: Prevents audio clipping by hard-limiting signal peaks, acts as final safety net against amplitude spikes that could damage speakers or cause harsh audio
- When to enable: If you experience sudden loud pops, crackling, or signal overload

## Customization Notes

**Location-Specific Tuning:**
Location of the RTL-SDR and antenna will have different signal conditions. Enable/disable processing blocks based on your specific signal quality. Strong signals may need fewer processing blocks, while weak signals may benefit from all available processing.

**Adding More Blocks:**
The flowgraph can be extended with additional processing blocks like:
- Band Pass Filters for precise frequency shaping
- Squelch blocks for silence detection  
- Multiple AGC stages for complex gain management
- Noise reduction algorithms
- Audio compressors/limiters

---

# Development Tips

## Frequency Planning

**Common VHF Marine Frequencies:**
- **Channel 16**: 156.800 MHz (Emergency/Calling)
- **Channel 6**: 156.300 MHz (Intership Safety)  
- **Channel 9**: 156.450 MHz (Commercial/Non-Commercial)
- **Channel 13**: 156.650 MHz (Navigation Safety)

**Weather Stations:**
- **Victoria, BC**: 162.4006 MHz
- **Vancouver, BC**: 162.550 MHz  
- **Seattle, WA**: 162.550 MHz

---

# Variable Reference Guide

This section provides comprehensive details on all GNU Radio Companion variables used in the flowgraph. Refer to this when tuning parameters or adapting the system for different locations.

## Core System Variables

### **samp_rate** - RTL-SDR Sample Rate
Purpose: Controls how fast the RTL-SDR samples incoming radio signals
Options:
- `240000` (240 kHz) - Minimum for narrow band signals, very low CPU
- `480000` (480 kHz) 
- `960000` (960 kHz) - **Recommended** - optimal for VHF weather/marine
- `1200000` (1.2 MHz)
- `1800000` (1.8 MHz)
- `2048000` (2.048 MHz) - Maximum bandwidth needed
Hardware Constraints: Your RTL-SDR may not support all options
Impact: Higher rates = more bandwidth captured but more CPU usage

### **audio_rate** - Final Audio Output Rate  
Value: 48000 (48 kHz) (Don't change unless you have specific audio system requirements)
Purpose: Audio output rate for streaming

### **frequency** - Target Radio Frequency
Purpose: Tunes RTL-SDR to specific radio station
- `156.8e6` - Marine Channel 16 (emergency frequency) *Production*
- `162.4006e6` - Victoria Weather Station *Development Testing*
- `162.550e6` - Vancouver Weather Station
Format: Use scientific notation (e6 = × 1,000,000)

### **rf_gain** - RTL-SDR Hardware Gain
Purpose: Controls RTL-SDR amplification (when AGC=False)
- When Hardware AGC=True (recommended), this setting is overridden by automatic gain control
- Even in AGC=True, a rf_gain value must be set. 40 is a good default. 
Range: Different RTL-SDR's will gave different ranges. The test RTL-SDR had the following optins:
[0.0, 0.9, 1.4, 2.7, 3.7, 7.7, 8.7, 12.5, 14.4, 15.7, 16.6, 19.7, 20.7, 
22.9, 25.4, 28.0, 29.7, 32.8, 33.8, 36.4, 37.2, 38.6, 40.2, 42.1, 43.4, 
 43.9, 44.5, 48.0, 49.6]


## Calculated Variables

### **quad_rate** - WBFM Quadrature Rate
Purpose: Intermediate processing rate for FM demodulation
Calculation: `audio_rate * audio_decim`
Typical Values: 192000 (48k × 4), 176400 (44.1k × 4)

### **audio_decim** - Audio Decimation Factor
Purpose: How much WBFM reduces quad_rate to audio_rate
Common Values: 4 (most common), 8 (for higher quad rates)

### **resamp_interp** & **resamp_decim** - Resampler Ratios
Purpose: Reduces samp_rate to quad_rate efficiently. Auto-calculated using samp_rate and quad_rate.
**Calculation:** Uses `math.gcd(samp_rate, quad_rate)` for optimal ratios
**Examples:**
- 960k → 192k = 1:5 ratio
- 480k → 192k = 2:5 ratio  
- 2048k → 192k = 3:32 ratio

## Optional Processing Variables

### **agc_rate** - AGC Response Speed
Purpose: How fast AGC2 responds to level changes
Range: 1e-6 (very slow) to 1e-3 (very fast)
Recommendations:
- `1e-6` - Extremely gentle, for very stable signals
- `1e-5` - **Recommended** - gentle, reduces artifacts
- `1e-4` - Moderate response for varying signals
- `1e-3` - Fast response, may cause "pumping"

### **agc_reference** - AGC Target Level  
Purpose: What audio level AGC2 tries to maintain
Range: 0.05 to 0.8
Guidelines:
- `0.05-0.2` - Conservative, leaves headroom for peaks
- `0.3-0.5` - Moderate levels, good for most applications
- `0.6-0.8` - High levels, risk of clipping

### **agc_gain** - AGC Initial Gain
Purpose: Starting gain multiplier for AGC2
Typical Range: 0.5 to 2.0
Usage: Usually left at 1.0, AGC adjusts automatically

### **highpass_cutoff** - High Pass Filter Frequency
Purpose: Removes low-frequency rumble and noise
Practical Range:
- `100-200` Hz - Removes very low rumble only
- `300-400` Hz - **Recommended** - removes rumble, preserves voice
- `500-600` Hz - Aggressive, may affect low voices

### **cutoff_freq** - Low Pass Filter Frequency  
Purpose: Removes high-frequency static and hiss
Common Values:
- `6000-8000` Hz - Aggressive static removal, may muffle voice
- `10000-12000` Hz - **Recommended** - good balance
- `15000-18000` Hz - Minimal filtering, preserves all voice harmonics

### **rail_low** & **rail_high** - Hard Limiter Clipping Levels
Purpose: Prevents audio clipping by hard-limiting signal peaks
Digital Audio Range:
- Digital audio systems use -1.0 to +1.0 as the full scale range
- If sound is beyond ±1.0 = Hard clipping, distortion, potential equipment damage

Guidelines for rail_low, rail_high:
- `±0.6` - Very conservative, significant headroom, may limit dynamics
- `±0.8` - **Recommended** - good protection with adequate headroom
- `±0.9` - Aggressive, minimal headroom, risk of occasional clipping
- `±1.0` - Dangerous, no headroom, guaranteed distortion on peaks

---

# Custom Icecast Sink Development

## Understanding the Custom Icecast Sink

The VHF system uses a custom GNU Radio block for streaming audio directly to Icecast with real-time MP3 encoding. This custom functionality is embedded in the GRC file (`gnuradio/vhfListeningGRC.grc`) as an "Embedded Python Block".

### Why a Custom Block?

Standard GNU Radio doesn't include direct Icecast streaming. The custom block:
- Handles real-time MP3 encoding using `lameenc`
- Manages Icecast connection and streaming with `python-shout`
- Loads configuration from `.env` files
- Includes robust error handling and logging

## Restoring the Custom Icecast Sink

If the custom icecast sink gets accidentally deleted from the GRC file, here are your recovery options:

### Option 1: Git Restore (Recommended)

**Quick Recovery:**
```bash
# Check what changed
git status
git diff gnuradio/vhfListeningGRC.grc

# Restore the GRC file
git checkout -- gnuradio/vhfListeningGRC.grc

# Regenerate Python files
cd gnuradio
gnuradio-companion vhfListeningGRC.grc
# Click "Generate" button, then exit
```

### Option 2: Manual Recreation (Simple with VSCode)

First, install VSCode as the default editor to enable easy copy-paste editing of embedded Python blocks. 
Without setting vscode as the default terminal, GNURadio-companion will open the boilerplate Embedded Python Block with Vim, which has no easy copy paste options. 

#### Step 1: Setup VSCode as Default Editor (One-time setup)

Easily install VSCode via "Pi Apps" on Linux OR via the terminal:

```bash
sudo apt update && sudo apt install code
```

Then, set VSCode as default editor for text files:

```bash
xdg-mime default code.desktop text/plain
```

#### Step 2: Create the Embedded Python Block
1. **Open GNU Radio Companion:**
   ```bash
   gnuradio-companion gnuradio/vhfListeningGRC.grc
   ```

2. **Add the block:**
   - In the right sidebar, search for "Python Block"
   - Drag and drop it into the flowgraph
   - Connect it at the end of the pipeline (where the original icecast sink was)

3. **Open for editing:**
   - Double-click the "Embedded Python Block" to open properties
   - Under "General" → "Code", click "Open in Editor"
   - **VSCode opens** with the boilerplate template

#### Step 3: Replace with Custom Icecast Code

**VSCode will show this boilerplate:**
```python
"""
Embedded Python Blocks:

Each time this file is saved, GRC will instantiate the first class it finds
to get ports and parameters of your block. The arguments to __init__  will
be the parameters. All of them are required to have default values!
"""

import numpy as np
from gnuradio import gr

class blk(gr.sync_block):  # other base classes are basic_block, decim_block, interp_block
    """Embedded Python Block example - a simple multiply const"""

    def __init__(self, example_param=1.0):  # only default arguments here
        """arguments to this function show up as parameters in GRC"""
        gr.sync_block.__init__(
            self,
            name='Embedded Python Block',   # will show up in GRC
            in_sig=[np.complex64],
            out_sig=[np.complex64]
        )
        # if an attribute with the same name as a parameter is found,
        # a callback is registered (properties work, too).
        self.example_param = example_param

    def work(self, input_items, output_items):
        """example: multiply with constant"""
        output_items[0][:] = input_items[0] * self.example_param
        return len(output_items[0])
```

**Replace the entire file contents with:**
1. **Open** `gnuradio/icecast_sink.py` in another VSCode tab
2. **Copy everything** from `icecast_sink.py`
3. **Paste into the embedded block file**, replacing all the boilerplate
4. **Save the file** in VSCode

#### Step 4: Generate and Test
1. **Return to GNU Radio Companion**
2. **Click "Generate"** (📦↓ icon) to create `options_0.py` and `options_0_epy_block_0.py`
3. **Test the implementation:**
   ```bash
   cd gnuradio
   python3 options_0.py
   ```

**Expected output:**
- RTL-SDR Blog V4 detection
- MP3 encoder initialization
- Icecast connection success
- Audio streaming to your configured server

#### Step 5: Verify Connection
Connect the block in the flowgraph:
- **Input**: Connect from `analog_rail_ff_0` output
- **No output**: It's a sink block (audio goes to Icecast)

The embedded block should now work identically to the original implementation!

### Option 3: Direct GRC File Editing (Advanced)

If you're comfortable with XML editing, you can directly edit the GRC file:

1. Open `gnuradio/vhfListeningGRC.grc` in a text editor
2. Find the `epy_block_0` section
3. Locate the `_source_code` parameter
4. Replace the code content with the implementation from `icecast_sink.py`

**Note:** The code in the GRC file is stored as a single escaped string, making this approach error-prone.

## Protected Files

Always commit these files to protect the custom functionality:

1. **`gnuradio/vhfListeningGRC.grc`** - Contains the embedded block (primary)
2. **`gnuradio/icecast_sink.py`** - Master copy of implementation (backup)
3. **`gnuradio/options_0_epy_block_0.py`** - Generated file (auto-created)
4. **`services/vhf-gnuradio.service`** - Includes RTL-SDR v4 environment fix

## Development Notes

**Key Differences Between Standalone and Embedded:**
- **Standalone class**: `icecast_sink` (in icecast_sink.py)
- **Embedded class**: `blk` (required by GNU Radio Companion)
- Both implementations are functionally identical

**Why We Edited GRC Directly:**
The GNU Radio Companion embedded block workflow was problematic:
- **"Open in Editor" launches vim without clipboard access**
- No copy-paste capability from external files
- Difficult to understand which boilerplate template parts to preserve
- Managing the class name requirement (`blk` vs `icecast_sink`)
- Risk of vim syntax errors breaking the block

**Solution:** Direct GRC XML file editing bypassed these GUI limitations and provided:
- Full clipboard access for copying code
- Precise control over the embedded implementation
- Ability to preserve the exact working code structure