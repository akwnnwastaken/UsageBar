using Xunit;

// These tests spawn real process trees, flood pipes to prove the output bound,
// and measure how long a deadline takes to fire. Running several of those at
// once on a two-core CI runner distorts exactly what they measure: a helper
// process starved of CPU can miss a deadline that the product code honored
// perfectly well.
//
// Serial execution costs about a minute of CI time and removes that variance.
[assembly: CollectionBehavior(DisableTestParallelization = true)]
