#ifndef CVORBIS_H
#define CVORBIS_H

// Minimal interface to the vendored stb_vorbis decoder (stb_vorbis.c).
// Decodes an in-memory OGG Vorbis file to interleaved 16-bit PCM.
// Returns the number of samples per channel, or a negative value on error.
// On success, *output points to a malloc'd interleaved short buffer that the
// caller must free().
int stb_vorbis_decode_memory(const unsigned char *mem, int len,
                             int *channels, int *sample_rate, short **output);

#endif /* CVORBIS_H */
