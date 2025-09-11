#!/usr/bin/env python3
# -*- coding: utf-8 -*-

#
# SPDX-License-Identifier: GPL-3.0
#
# GNU Radio Python Flow Graph
# Title: VHF Listening Station
# GNU Radio version: 3.10.9.2

from gnuradio import analog
from gnuradio import blocks
from gnuradio import filter
from gnuradio.filter import firdes
from gnuradio import gr
from gnuradio.fft import window
import sys
import signal
from argparse import ArgumentParser
from gnuradio.eng_arg import eng_float, intx
from gnuradio import eng_notation
from gnuradio import soapy
import math




class options_0(gr.top_block):

    def __init__(self):
        gr.top_block.__init__(self, "VHF Listening Station", catch_exceptions=True)

        ##################################################
        # Variables
        ##################################################
        self.audio_rate = audio_rate = 48000
        self.audio_decim = audio_decim = 4
        self.samp_rate = samp_rate = 240000
        self.quad_rate = quad_rate = audio_rate*audio_decim
        self.gcd_value = gcd_value = math.gcd(int(samp_rate), int(quad_rate))
        self.rfGain = rfGain = 48
        self.lowpass_trans_width = lowpass_trans_width = 3000
        self.lowpass_cutoff_freq = lowpass_cutoff_freq = 12000
        self.interp = interp = int(quad_rate / gcd_value)
        self.highpass_trans_width = highpass_trans_width = 50
        self.highpass_cutoff_freq = highpass_cutoff_freq = 300
        self.freq = freq = 162.400e6
        self.decim = decim = int(samp_rate / gcd_value)
        self.agc_reference = agc_reference = 0.3
        self.agc_rate = agc_rate = 1e-5
        self.agc_gain = agc_gain = 1.0

        ##################################################
        # Blocks
        ##################################################

        self.soapy_rtlsdr_source_0 = None
        dev = 'driver=rtlsdr'
        stream_args = 'bufflen=16384'
        tune_args = ['']
        settings = ['']

        def _set_soapy_rtlsdr_source_0_gain_mode(channel, agc):
            self.soapy_rtlsdr_source_0.set_gain_mode(channel, agc)
            if not agc:
                  self.soapy_rtlsdr_source_0.set_gain(channel, self._soapy_rtlsdr_source_0_gain_value)
        self.set_soapy_rtlsdr_source_0_gain_mode = _set_soapy_rtlsdr_source_0_gain_mode

        def _set_soapy_rtlsdr_source_0_gain(channel, name, gain):
            self._soapy_rtlsdr_source_0_gain_value = gain
            if not self.soapy_rtlsdr_source_0.get_gain_mode(channel):
                self.soapy_rtlsdr_source_0.set_gain(channel, gain)
        self.set_soapy_rtlsdr_source_0_gain = _set_soapy_rtlsdr_source_0_gain

        def _set_soapy_rtlsdr_source_0_bias(bias):
            if 'biastee' in self._soapy_rtlsdr_source_0_setting_keys:
                self.soapy_rtlsdr_source_0.write_setting('biastee', bias)
        self.set_soapy_rtlsdr_source_0_bias = _set_soapy_rtlsdr_source_0_bias

        self.soapy_rtlsdr_source_0 = soapy.source(dev, "fc32", 1, '',
                                  stream_args, tune_args, settings)

        self._soapy_rtlsdr_source_0_setting_keys = [a.key for a in self.soapy_rtlsdr_source_0.get_setting_info()]

        self.soapy_rtlsdr_source_0.set_sample_rate(0, samp_rate)
        self.soapy_rtlsdr_source_0.set_frequency(0, freq)
        self.soapy_rtlsdr_source_0.set_frequency_correction(0, 0)
        self.set_soapy_rtlsdr_source_0_bias(bool(False))
        self._soapy_rtlsdr_source_0_gain_value = rfGain
        self.set_soapy_rtlsdr_source_0_gain_mode(0, bool(True))
        self.set_soapy_rtlsdr_source_0_gain(0, 'TUNER', rfGain)
        self.rational_resampler_xxx_0 = filter.rational_resampler_ccc(
                interpolation=interp,
                decimation=decim,
                taps=[],
                fractional_bw=0)
        self.blocks_file_sink_0 = blocks.file_sink(gr.sizeof_float*1, '/tmp/vhf_audio_pipe', False)
        self.blocks_file_sink_0.set_unbuffered(True)
        self.analog_rail_ff_0 = analog.rail_ff((-.8), 0.8)
        self.analog_nbfm_rx_0 = analog.nbfm_rx(
        	audio_rate=audio_rate,
        	quad_rate=quad_rate,
        	tau=(75e-6),
        	max_dev=5e3,
          )


        ##################################################
        # Connections
        ##################################################
        self.connect((self.analog_nbfm_rx_0, 0), (self.analog_rail_ff_0, 0))
        self.connect((self.analog_rail_ff_0, 0), (self.blocks_file_sink_0, 0))
        self.connect((self.rational_resampler_xxx_0, 0), (self.analog_nbfm_rx_0, 0))
        self.connect((self.soapy_rtlsdr_source_0, 0), (self.rational_resampler_xxx_0, 0))


    def get_audio_rate(self):
        return self.audio_rate

    def set_audio_rate(self, audio_rate):
        self.audio_rate = audio_rate
        self.set_quad_rate(self.audio_rate*self.audio_decim)
        self.high_pass_filter_0.set_taps(firdes.high_pass(1, self.audio_rate, self.highpass_cutoff_freq, self.highpass_trans_width, window.WIN_KAISER, 6.76))
        self.low_pass_filter_0.set_taps(firdes.low_pass(1, self.audio_rate, self.lowpass_cutoff_freq, self.lowpass_trans_width, window.WIN_KAISER, 6.76))

    def get_audio_decim(self):
        return self.audio_decim

    def set_audio_decim(self, audio_decim):
        self.audio_decim = audio_decim
        self.set_quad_rate(self.audio_rate*self.audio_decim)

    def get_samp_rate(self):
        return self.samp_rate

    def set_samp_rate(self, samp_rate):
        self.samp_rate = samp_rate
        self.set_decim(int(self.samp_rate / self.gcd_value))
        self.set_gcd_value(math.gcd(int(self.samp_rate), int(self.quad_rate)))
        self.soapy_rtlsdr_source_0.set_sample_rate(0, self.samp_rate)

    def get_quad_rate(self):
        return self.quad_rate

    def set_quad_rate(self, quad_rate):
        self.quad_rate = quad_rate
        self.set_gcd_value(math.gcd(int(self.samp_rate), int(self.quad_rate)))
        self.set_interp(int(self.quad_rate / self.gcd_value))

    def get_gcd_value(self):
        return self.gcd_value

    def set_gcd_value(self, gcd_value):
        self.gcd_value = gcd_value
        self.set_decim(int(self.samp_rate / self.gcd_value))
        self.set_interp(int(self.quad_rate / self.gcd_value))

    def get_rfGain(self):
        return self.rfGain

    def set_rfGain(self, rfGain):
        self.rfGain = rfGain
        self.set_soapy_rtlsdr_source_0_gain(0, 'TUNER', self.rfGain)

    def get_lowpass_trans_width(self):
        return self.lowpass_trans_width

    def set_lowpass_trans_width(self, lowpass_trans_width):
        self.lowpass_trans_width = lowpass_trans_width
        self.low_pass_filter_0.set_taps(firdes.low_pass(1, self.audio_rate, self.lowpass_cutoff_freq, self.lowpass_trans_width, window.WIN_KAISER, 6.76))

    def get_lowpass_cutoff_freq(self):
        return self.lowpass_cutoff_freq

    def set_lowpass_cutoff_freq(self, lowpass_cutoff_freq):
        self.lowpass_cutoff_freq = lowpass_cutoff_freq
        self.low_pass_filter_0.set_taps(firdes.low_pass(1, self.audio_rate, self.lowpass_cutoff_freq, self.lowpass_trans_width, window.WIN_KAISER, 6.76))

    def get_interp(self):
        return self.interp

    def set_interp(self, interp):
        self.interp = interp

    def get_highpass_trans_width(self):
        return self.highpass_trans_width

    def set_highpass_trans_width(self, highpass_trans_width):
        self.highpass_trans_width = highpass_trans_width
        self.high_pass_filter_0.set_taps(firdes.high_pass(1, self.audio_rate, self.highpass_cutoff_freq, self.highpass_trans_width, window.WIN_KAISER, 6.76))

    def get_highpass_cutoff_freq(self):
        return self.highpass_cutoff_freq

    def set_highpass_cutoff_freq(self, highpass_cutoff_freq):
        self.highpass_cutoff_freq = highpass_cutoff_freq
        self.high_pass_filter_0.set_taps(firdes.high_pass(1, self.audio_rate, self.highpass_cutoff_freq, self.highpass_trans_width, window.WIN_KAISER, 6.76))

    def get_freq(self):
        return self.freq

    def set_freq(self, freq):
        self.freq = freq
        self.soapy_rtlsdr_source_0.set_frequency(0, self.freq)

    def get_decim(self):
        return self.decim

    def set_decim(self, decim):
        self.decim = decim

    def get_agc_reference(self):
        return self.agc_reference

    def set_agc_reference(self, agc_reference):
        self.agc_reference = agc_reference
        self.analog_agc2_xx_0.set_reference(self.agc_reference)

    def get_agc_rate(self):
        return self.agc_rate

    def set_agc_rate(self, agc_rate):
        self.agc_rate = agc_rate
        self.analog_agc2_xx_0.set_attack_rate(self.agc_rate)
        self.analog_agc2_xx_0.set_decay_rate(self.agc_rate)

    def get_agc_gain(self):
        return self.agc_gain

    def set_agc_gain(self, agc_gain):
        self.agc_gain = agc_gain
        self.analog_agc2_xx_0.set_gain(self.agc_gain)




def main(top_block_cls=options_0, options=None):
    tb = top_block_cls()

    def sig_handler(sig=None, frame=None):
        tb.stop()
        tb.wait()

        sys.exit(0)

    signal.signal(signal.SIGINT, sig_handler)
    signal.signal(signal.SIGTERM, sig_handler)

    tb.start()

    tb.wait()


if __name__ == '__main__':
    main()
