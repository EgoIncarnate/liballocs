#ifndef LIBALLOCS_BITOPS_H_
#define LIBALLOCS_BITOPS_H_

#ifdef __cplusplus
extern "C" {
#endif

/* We want the various inline functions in here to behave like 
 * macros: always inline. Use some macros to abbreviate this
 * and allow overriding by the client. */
#ifndef INLINE_DECL
#define INLINE_DECL extern inline
#endif

#ifndef INLINE_ATTRS
#define INLINE_ATTRS __attribute__((always_inline,gnu_inline))
#endif

INLINE_DECL int is_power_of_two(size_t i) INLINE_ATTRS;
INLINE_DECL int INLINE_ATTRS is_power_of_two(size_t i)
{
	/* If we are a power of two, then one less than us 
	 * has a run of low-order bits set and no others set,
	 * whereas we have a single (higher) bit set. So when
	 * we AND, we get zero. In all other (non-power-of-two)
	 * cases except zero, not all lower-order bits will
	 * roll over between i-1 and i, so there will be a nonzero
	 * AND. */
	return (i != 0) && !(i & (i - 1));
}

// stolen from Hacker's Delight, then updated for 64 bits
INLINE_DECL int nlz1(unsigned long x) INLINE_ATTRS;
INLINE_DECL int INLINE_ATTRS nlz1(unsigned long x)
{
	int n;

	if (x == 0) return 64;
	n = 0;

	if (x <= 0x00000000FFFFFFFFL) { n += 32; x <<= 32; }
	if (x <= 0x0000FFFFFFFFFFFFL) { n += 16; x <<= 16; }
	if (x <= 0x00FFFFFFFFFFFFFFL) { n += 8;  x <<= 8; }
	if (x <= 0x0FFFFFFFFFFFFFFFL) { n += 4;  x <<= 4; }
	if (x <= 0x3FFFFFFFFFFFFFFFL) { n += 2;  x <<= 2; }
	if (x <= 0x7FFFFFFFFFFFFFFFL) { n += 1;  x <<= 1; }
	
	return n;
}

#define BOTTOM_N_BITS_SET(n) \
 ( ( (n)==0 ) ? 0 : ((n) == 8*sizeof(uintptr_t) ) \
 	? (~((uintptr_t)0)) \
	: ((((uintptr_t)1u) << ((n))) - 1))
#define BOTTOM_N_BITS_CLEAR(n) (~(BOTTOM_N_BITS_SET((n))))

#define TOP_N_BITS_SET(n)      (BOTTOM_N_BITS_CLEAR(8*(sizeof(uintptr_t))-((n))))
#define TOP_N_BITS_CLEAR(n)    (BOTTOM_N_BITS_SET(8*(sizeof(uintptr_t))-((n))))
#define NBITS(t) ((sizeof (t))<<3)
#define UNSIGNED_LONG_NBITS (NBITS(unsigned long))
/* Thanks to Martin Buchholz -- <http://www.wambold.com/Martin/writings/alignof.html> */
#ifndef ALIGNOF
#define ALIGNOF(type) offsetof (struct { char c; type member; }, member)
#endif
#define PAD_TO_ALIGN(n, a) 	((0 == ((n) % (a))) ? (n) : (n) + (a) - ((n) % (a)))

INLINE_DECL int next_power_of_two_ge(size_t i) INLINE_ATTRS;
INLINE_DECL int INLINE_ATTRS next_power_of_two_ge(size_t i)
{
	if (is_power_of_two(i)) return i;
	else 
	{
		int nlz = nlz1(i);
		unsigned long highest_power = 1ul<<(NBITS(size_t) - nlz - 1); // e.g. <<63 for no leading zeroes
		return highest_power << 1;
	}
}

/* The integer log 2 of a power of two is the number of trailing zeroes.
 * FIXME: use Hacker's Delight code here. */
INLINE_DECL unsigned integer_log2(size_t i) INLINE_ATTRS;
INLINE_DECL unsigned INLINE_ATTRS integer_log2(size_t i)
{
	unsigned count = 0;
	assert(i != 0);
	while ((i & 0x1) == 0) { ++count; i >>= 1; }
	assert(i == 1);
	return count;
}

#ifdef __cplusplus
} /* end extern "C" */
#endif

#endif
