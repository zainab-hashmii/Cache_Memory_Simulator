# Cache Memory Simulator — Complete Project Documentation
### x86 Assembly Language | MASM/TASM | Semester Project

---

## Table of Contents
1. Project Overview
2. How to Assemble and Run
3. Memory Structure — How the Cache is Stored
4. Address Decoding Logic
5. Mapping Technique Explanations
6. Replacement Policy (FIFO)
7. Code Architecture — Procedures Summary
8. Example Run (Step-by-Step)

---

## 1. Project Overview

This simulator demonstrates three classic cache-mapping strategies entirely in
16-bit x86 Assembly using DOS INT 21h calls for I/O.

| Feature | Detail |
|---------|--------|
| Cache lines | 4 |
| Block size | 4 bytes (offset = 2 bits) |
| Address width | 8 bits (0–255) |
| Mapping modes | Direct / Fully Associative / Set-Associative 2-way |
| Replacement | FIFO (for associative modes) |
| Statistics | Hits, Misses, Hit Ratio % |

---

## 2. How to Assemble and Run

### Using TASM (Turbo Assembler)

```
TASM cache_simulator.asm
TLINK cache_simulator.obj
cache_simulator.exe
```

### Using MASM (Microsoft Macro Assembler)

```
ML cache_simulator.asm /link
cache_simulator.exe
```

### Running in DOSBox (Windows/Linux/Mac)

1. Install DOSBox from https://www.dosbox.com
2. Mount your folder:  `mount c c:\myproject`
3. Switch:  `c:`
4. Assemble and run as above.

---

## 3. Memory Structure — How the Cache is Stored

The cache is modelled using parallel byte arrays in the DATA segment.

### Direct-Mapped Cache (4 lines)

```
OFFSET:       0     1     2     3
dm_valid  [ 0   | 0   | 0   | 0   ]   1 byte per line  (0=invalid, 1=valid)
dm_tag    [0xFF |0xFF |0xFF |0xFF ]   1 byte per line  (tag stored here)
```

Physical layout in RAM (conceptual):

```
Line 0: [valid=1 byte][tag=1 byte]
Line 1: [valid=1 byte][tag=1 byte]
Line 2: [valid=1 byte][tag=1 byte]
Line 3: [valid=1 byte][tag=1 byte]
```

Accessed via:  `dm_valid[SI]`  and  `dm_tag[SI]`  where SI = index.

### Fully-Associative Cache (4 lines)

Identical layout but no fixed index — every line is searched sequentially.

```
fa_valid  [ 0 | 0 | 0 | 0 ]
fa_tag    [FF|FF|FF|FF]
fa_fifo   [ 0 ]              <- next eviction pointer (0–3)
```

### Set-Associative Cache (2 sets × 2 ways)

Flattened 2D array:  index = set * WAYS + way

```
Index:        0       1       2       3
              Set0    Set0    Set1    Set1
              Way0    Way1    Way0    Way1
sa_valid  [  0   |  0   |  0   |  0  ]
sa_tag    [ FF   | FF   | FF   | FF  ]
sa_fifo   [ 0    | 0   ]    <- one FIFO pointer per set
```

---

## 4. Address Decoding Logic

All addresses are 8-bit (0–255).  The bit field layout changes per mode.

### Direct-Mapped  (bits: tag=4, index=2, offset=2)

```
  Bit:   7  6  5  4  |  3  2  |  1  0
         +-----------+--------+------+
         |   TAG(4)  | IDX(2) | OFF  |
         +-----------+--------+------+

  offset = address AND 0x03
  index  = (address >> 2) AND 0x03
  tag    = address >> 4
```

Example: address = 0xA5 = 1010 0101

```
  Binary:  1010 | 01 | 01
  tag    = 1010 = 10
  index  = 01   = 1
  offset = 01   = 1
```

→ Check dm_valid[1].  If valid AND dm_tag[1]==10  → HIT.
   Otherwise → MISS, load tag 10 into line 1.

### Fully Associative  (bits: tag=6, offset=2)

```
  Bit:   7  6  5  4  3  2  |  1  0
         +------------------+------+
         |      TAG (6)     | OFF  |
         +------------------+------+

  offset = address AND 0x03
  tag    = address >> 2
```

→ Search ALL 4 lines for matching tag → HIT.
   If not found → MISS, replace line pointed to by fa_fifo.

### Set-Associative 2-way  (bits: tag=5, set=1, offset=2)

```
  Bit:   7  6  5  4  3  |  2  |  1  0
         +--------------+-----+------+
         |    TAG (5)   | SET | OFF  |
         +--------------+-----+------+

  offset = address AND 0x03
  set    = (address >> 2) AND 0x01
  tag    = address >> 3
```

→ Search both ways in the given set → HIT/MISS.
   MISS: evict way indicated by sa_fifo[set], flip sa_fifo[set] (0↔1).

---

## 5. Mapping Technique Explanations

### 5.1  Direct Mapping

Each memory block maps to **exactly one** cache line determined by:

```
  cache_line = (block_number) MOD (number_of_cache_lines)
```

**Advantages**
- Simple and fast — no search required, O(1) lookup.
- Low hardware cost.

**Disadvantages**
- Thrashing: two blocks that map to the same line evict each other
  even when other lines are free.
- Hit rate can be poor for certain access patterns.

**Hardware analogy**
Think of a parking lot where car plate ending in 0 must park in spot 0,
ending in 1 must park in spot 1, etc. No flexibility.

---

### 5.2  Fully Associative Mapping

A block can be placed in **any** cache line.

```
  Search: compare tag against ALL lines in parallel (hardware) /
          sequentially (this simulator).
```

**Advantages**
- No thrashing — maximum flexibility.
- Highest possible hit rate for a given cache size.

**Disadvantages**
- Expensive hardware (comparators for every line).
- Slower lookup (sequential in software).

**Replacement needed** because any line can hold any block → must choose
a victim when the cache is full.  This simulator uses **FIFO**.

---

### 5.3  Set-Associative Mapping (2-way)

A compromise: cache is divided into **sets**; a block maps to one set
(like direct mapping) but can go in **any way** within that set
(like fully associative).

```
  set  = block_number MOD number_of_sets
  Within the set: search all WAYS for a tag match.
```

**Advantages**
- Reduces thrashing vs direct mapping.
- Less hardware than fully associative.

**Disadvantages**
- More complex than direct mapping.

Most real CPUs (Intel Core, ARM Cortex) use 4-way, 8-way, or 16-way
set-associative caches.

---

## 6. Replacement Policy — FIFO

**First-In First-Out**: the block that entered the cache earliest
is evicted first.

**Implementation in this simulator**:

- `fa_fifo` (1 byte): points to the next line to overwrite (0–3).
  After each replacement, pointer = (pointer + 1) MOD 4.

- `sa_fifo[set]` (1 bit per set): toggles between way 0 and way 1.
  When set to 0, next miss evicts way 0 and flips to 1; vice versa.

**FIFO vs LRU**

| Property | FIFO | LRU |
|----------|------|-----|
| Implementation | Simple counter | Timestamps / stack |
| Performance | Good | Better (locality-aware) |
| Hardware cost | Low | Higher |

---

## 7. Code Architecture — Procedures

| Procedure | Purpose |
|-----------|---------|
| `main` | Menu loop, dispatches on user choice |
| `choose_mapping` | Sets `map_mode` (1/2/3) |
| `access_address` | Reads address, calls correct mapper |
| `direct_access` | Direct-map hit/miss logic |
| `full_access` | Fully-associative hit/miss logic |
| `set_access` | Set-associative hit/miss logic |
| `show_cache` | Prints formatted cache table |
| `show_statistics` | Prints hit/miss counts and ratio |
| `reset_cache` | Zeros all arrays and counters |
| `print_str` | INT 21h AH=09h string output |
| `read_char` | INT 21h AH=01h single key input |
| `read_decimal` | Reads up to 3 decimal digits into BX |
| `print_decimal` | Prints AX as unsigned decimal |

**Register conventions used throughout**

| Register | Role |
|----------|------|
| AX | General arithmetic, I/O function codes |
| BX | Array indexing, intermediate values |
| CX | Tag value, loop counter |
| DX | String pointer for INT 21h, temporary |
| SI | Line / set index |
| DI | Way index / offset |

---

## 8. Example Run (Step-by-Step)

### Setup

- Mode: **Direct Mapped**
- Cache: 4 lines, all empty at start
- Address bits: tag(4) | index(2) | offset(2)

### Access Sequence:  5, 21, 37, 5, 69, 21

---

**Access 1 — Address 5  (binary: 0000 0101)**

```
  tag    = 0000  = 0
  index  = 01    = 1
  offset = 01    = 1

  Line 1: valid=0  → MISS
  Action: store tag=0 in line 1, set valid=1
```

Cache state:
```
  Line | Valid | Tag
  -----+-------+----
    0  |  No   |  --
    1  |  Yes  |   0
    2  |  No   |  --
    3  |  No   |  --
```
Stats: Accesses=1  Hits=0  Misses=1  Ratio=0%

---

**Access 2 — Address 21  (binary: 0001 0101)**

```
  tag    = 0001  = 1
  index  = 01    = 1
  offset = 01    = 1

  Line 1: valid=1, stored tag=0, incoming tag=1  → MISMATCH → MISS
  Action: replace line 1 with tag=1
```

Cache state:
```
  Line | Valid | Tag
  -----+-------+----
    0  |  No   |  --
    1  |  Yes  |   1
    2  |  No   |  --
    3  |  No   |  --
```
Stats: Accesses=2  Hits=0  Misses=2  Ratio=0%

---

**Access 3 — Address 37  (binary: 0010 0101)**

```
  tag    = 0010  = 2
  index  = 01    = 1
  offset = 01    = 1

  Line 1: valid=1, stored tag=1, incoming tag=2  → MISS
  Action: replace line 1 with tag=2
```

Stats: Accesses=3  Hits=0  Misses=3  Ratio=0%

---

**Access 4 — Address 5  (again)**

```
  tag=0, index=1
  Line 1: valid=1, stored tag=2, incoming tag=0  → MISS
  (tag 0 was evicted in step 2 — direct-map thrashing!)
```

Stats: Accesses=4  Hits=0  Misses=4  Ratio=0%

---

**Access 5 — Address 69  (binary: 0100 0101)**

```
  tag    = 0100  = 4
  index  = 01    = 1
  offset = 01    = 1

  Line 1 → MISS again.  (all map to line 1 — worst case!)
```

Stats: Accesses=5  Hits=0  Misses=5  Ratio=0%

---

**Access 6 — Address 21  (again)**

```
  tag=1, index=1
  Line 1: tag=4 → MISS
```

Stats: Accesses=6  Hits=0  Misses=6  **Ratio=0%**

---

**Observation**: addresses 5,21,37,69 all map to line 1 in direct mode
(thrashing).  Now repeat with **Fully Associative**:

### Same sequence in Fully-Associative Mode

```
Access 5  → MISS  (load: fa[0]=tag 1,  fifo→1)
Access 21 → MISS  (load: fa[1]=tag 5,  fifo→2)
Access 37 → MISS  (load: fa[2]=tag 9,  fifo→3)
Access 5  → HIT   (tag 1 found in fa[0])  ✓
Access 69 → MISS  (load: fa[3]=tag 17, fifo→0)
Access 21 → HIT   (tag 5 found in fa[1]) ✓
```

Stats: Accesses=6  Hits=2  Misses=4  **Ratio=33%**

This demonstrates why associative mapping achieves better hit rates.

---

*End of Documentation*

Project by: Zainab Hashmi
Course: Computer Organization and Assembely language
Semester: 4th
