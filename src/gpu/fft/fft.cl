__kernel void radix_fft(__global ulong4* src,
                        __global ulong4* dst,
                        __global ulong4* tpq,
                        __global ulong4* tom,
                        __local ulong4* tu,
                        uint n,
                        uint lgp,
                        uint deg, // 1=>radix2, 2=>radix4, 3=>radix8, ...
                        uint max_deg)
{
  __global field *x = src;
  __global field *y = dst;
  __global field *pq = tpq;
  __global field *omegas = tom;
  __local field *u = tu;

  uint32 lid = get_local_id(0);
  uint32 lsize = get_local_size(0);
  uint32 index = get_group_id(0);
  uint32 t = n >> deg;
  uint32 p = 1 << lgp;
  uint32 k = index & (p - 1);

  x += index;
  y += ((index - k) << deg) + k;

  uint32 count = 1 << deg; // 2^deg
  uint32 counth = count >> 1; // Half of count

  uint32 counts = count / lsize * lid;
  uint32 counte = counts + count / lsize;

  //////// ~30% of total time
  field twiddle = powmodcached(omegas, (n >> lgp >> deg) * k);
  ////////

  //////// ~35% of total time
  field tmp = powmod(twiddle, counts);
  for(uint32 i = counts; i < counte; i++) {
    u[i] = mulmod(tmp, x[i*t]);
    tmp = mulmod(tmp, twiddle);
  }
  barrier(CLK_LOCAL_MEM_FENCE);
  ////////

  //////// ~35% of total time
  uint32 pqshift = max_deg - deg;
  for(uint32 rnd = 0; rnd < deg; rnd++) {
    uint32 bit = counth >> rnd;
    for(uint32 i = counts >> 1; i < counte >> 1; i++) {
      uint32 di = i & (bit - 1);
      uint32 i0 = (i << 1) - di;
      uint32 i1 = i0 + bit;
      tmp = u[i0];
      u[i0] = addmod(u[i0], u[i1]);
      u[i1] = submod(tmp, u[i1]);
      if(di != 0) u[i1] = mulmod(pq[di << rnd << pqshift], u[i1]);
    }

    barrier(CLK_LOCAL_MEM_FENCE);
  }
  ////////

  for(uint32 i = counts >> 1; i < counte >> 1; i++) {
    y[i*p] = u[bitreverse(i, deg)];
    y[(i+counth)*p] = u[bitreverse(i + counth, deg)];
  }
}