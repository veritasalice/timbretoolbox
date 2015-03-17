function [c,f,t]=ERBpower(a,sr,cfarray,hopsize,bwfactor)
%ERBPOWER FFT-based cochlear power spectrogram
%  [C,F,T] = ERBPOWER(A,SR,CFARRAY,HOPSIZE,BWFACTOR) 
%  Power spectrogram with same frequency resolution and scale as human ear.
%
%  A: audio signal
%  sr: Hz - sampling rate
%  CFARRAY: array of channel frequencies (default: 1/2 ERB-spaced 30Hz-16 KHz)
%  HOPSIZE: s - interval between analyses (default: 0.01 s)
%  BWFACTOR: factor to apply to filter bandwidths (default=1)
%
%  C: spectrogram matrix
%  F: Hz - array of channel frequencies
%  T: s - array of times
%
%  Spectral resolution is similar to that of the cochlea, temporal resolution is
%  similar to the ERD of the impulse response of the lowest CF channels (about 20 ms).
%  This is about twice behavioral estimates of auditory temporal resolution (8-13 ms).
%
% See also ERB, ERBtohz, ERBfromhz, MakeERBCoeffs, spectrogram.

% AdC @ CNRS/Ircam 2001
% (c) 2001 CNRS

%  ERBPOWER splits the signal into overlapping frames and windows each with
%  a function shaped like the time-reversed envelope of a gammatone impulse 
%  response with parameters appropriate for a low-frequency cochlear filter,
%  with an equivalent rectangular duration (ERD) of about 20ms. 
%  The FFT size is set to the power of two immediately larger than twice
%  that value (sr*0.040), and the windowed slices are Fourier transformed to 
%  obtain a power spectrum.  
%  The frequency resolution is that of a "cf=0 Hz" channel, ie narrower than 
%  even the lowest cf channels, and the frequency axis is linear.  To get a
%  resolution similar to the cochlea, and channels evenly spaced on an 
%  equal-resolution scale (Cambridge ERBs), the power spectrum is remapped.  
%  Each channel of the new spectrum is the weighted sum of power spectrum
%  coefficients, obtained by forming the vector product with a weighting function 
%  so that the channel has its proper spectral width.  

% TODO: calibrate output magnitude scale (?).

if nargin < 1 | isempty(a); help ERBpower; return; end
if nargin < 2 | isempty(sr); error('need to specify sampling rate'); end
if nargin < 3 | isempty(cfarray)
	% space cfs at 1/2 ERB intervals from about 30Hz to 16kHz (or sr/2 if smaller):
	lo		= 30;                            % Hz - lower cf
	hi		= 16000;                         % Hz - upper cf
	hi		= min(hi, (sr/2-ERB(sr/2)/2));	% limit to 1/2 erb below Nyquist
	nchans	= round(2*(ERBfromhz(hi)-ERBfromhz(lo)));
	cfarray = ERBspace(lo,hi,nchans); 
end
[nchans,m]=size(cfarray);
if m>1; cfarray = cfarray'; if nchans>1; error('cfarray should be 1D'); end; nchans=m; end

if nargin < 4 | isempty(hopsize),	hopsize = 0.01; end   % s
if nargin < 5 | isempty(bwfactor),	bwfactor = 1;	end     
hopsize=hopsize*sr;	% --> samples

% Window size and shape are based on the envelope of the gammatone
% impulse response of the lowest CF channel, with ERB = 24.7 Hz. 
% The FFT window size is the smallest power of 2 larger than twice the 
% ERD of this window.
bw0		= 24.7;        	% Hz - base frequency of ERB formula (= bandwidth of "0Hz" channel)
b0		= bw0/0.982;    % gammatone b parameter (Hartmann, 1997)
ERD		= 0.495 / b0; 	% based on numerical calculation of ERD
wsize	= 2^nextpow2(ERD*sr*2);
window	= gtwindow(wsize, wsize/(ERD*sr));


% pad signal with zeros to align analysis point with window power centroid
[m,n]=size(a);
if m>1; a=a'; if n>1; error('signal should be 1D'); end; n=m; end
offset	= round(centroid(window.^2));
a		= [zeros(1,offset), a, zeros(1,wsize-offset)];

% matrix of windowed slices of signal
[fr,startsamples] = frames(a,wsize,hopsize);
nframes = size(fr,2);
fr		= fr .* repmat(window,1,nframes);  % apply window

% power spectrum
pwrspect = abs(fft(fr)).^2; clear 'fr';
pwrspect = pwrspect(1:wsize/2,:);
%plot(sum(pwrspect').^(1/3)); pause

% Power spectrum samples are weighted and summed (an operation similar to
% convolution, except that the convolution kernel changes from channel
% to channel).  The weighting function (kernel) for each channel is the
% power transfer function of a gammatone with a bandwidth equal to sqrt(b^2-b0^2).
% The rationale is:
% - by convolution the nominal bandwidth is b, which is what we want,
% - at low CFs the shape is dominated by the TF of the FFT window, ie OK,
% - at high CFs the shape is dominated by the kernel, also OK,
% - at intermediate CFs (around 200 Hz), the convolved shape turns out to
% quite close to the correct gammatone response shape (less than 3dB difference
% down to -50 dB from peak).

% array of kernel bandwidth coeffs:
b	= ERB(cfarray)/0.982; % ERB to gammatone b parameter
b	= b * bwfactor;
bb	= sqrt(b.^2 - b0.^2);			% factor 2 is for power

% test: compare desired gammatone response with result of convolution:
if (0)
	channel=20;
	[b(channel),bb(channel),cfarray(channel)]
	f	= (1:wsize/2)'*sr/wsize;
	z	= abs(1./(i*(f-cfarray(channel))+b(channel)).^4).^2;	% target
	z0	= abs(1./(i*(f-cfarray(channel))+b0).^4).^2;			% FFT window TF shape
	zz	= abs(1./(i*(f-cfarray(channel))+bb(channel)).^4).^2;	% kernel
	zz	= conv(zz,z0);											% convolve
	zz	= zz(round(cfarray(channel)*wsize/sr):end);				% shift so peaks match
	z	= z/max(z); zz = zz/max(zz); 
	plot(f, todb(z), 'r', (1:size(zz,1))'*sr/wsize, todb(zz), 'b'); 
	set(gca, 'xlim', [1, cfarray(channel)*3]); pause
end

% matrix of kernels (array of gammatone power tfs sampled at fft spectrum frequencies).
f		= repmat((1:wsize/2)'*sr/wsize,1,nchans);
cf		= repmat(cfarray',wsize/2,1);
bb		= repmat(bb',wsize/2,1);
wfunct			= abs(1./(i*(f - cf) + bb).^4).^2;		% power transfer functions
adjustweight	= ERB(cfarray') ./ sum(wfunct);			% adjust so weight == ERB
wfunct	= wfunct .* repmat(adjustweight, wsize/2, 1); 
wfunct	= wfunct/max(max(wfunct));


% multiply fft power spectrum matrix by weighting function matrix:
c = wfunct' * pwrspect; clear 'pwrspect';
f = cfarray';
t = startsamples/sr;
w = wfunct/max(max(wfunct));
