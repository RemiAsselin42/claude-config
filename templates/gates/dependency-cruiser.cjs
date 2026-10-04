/**
 * Architecture gates (frontend), created by /init-gates from
 * claude-config/templates/gates/dependency-cruiser.cjs. claude-config's arch-gates
 * workflow runs it with dependency-cruiser pinned there and --ignore-known against
 * .dependency-cruiser-known-violations.json (the frozen debt; it may only shrink).
 *
 * LAYERS goes from the lowest layer to the highest. Each entry is a regex matched
 * against the path right after src/ ('utils/' for a folder, '(App|main)\\.tsx$' for
 * files). A module may import its own layer or a lower one, never a higher one.
 * Same semantics as the Python gate: runtime imports only, direct edges,
 * module-level cycles, and a module in no layer is an error.
 *
 * @type {import('dependency-cruiser').IConfiguration}
 */
const SRC = '^src/';
const LAYERS = [
  // filled by /init-gates once the owner has approved the proposal, e.g.
  // ['types/', 'constants/'], ['utils/'], ['components/'], ['(App|main)\\.tsx$'],
];

const inLayers = (layers) => `${SRC}(${layers.flat().join('|')})`;
const classified = inLayers(LAYERS);

module.exports = {
  forbidden: [
    {
      name: 'no-circular',
      severity: 'error',
      comment: 'An import cycle makes the modules impossible to load or reason about in isolation.',
      from: {},
      to: { circular: true },
    },
    // one rule per layer: it may not import any layer above it
    ...LAYERS.slice(0, -1).map((layer, i) => ({
      name: `layer-${i}`,
      severity: 'error',
      comment: `Layer ${i} (${layer.join(', ')}) must not import a higher layer.`,
      from: { path: inLayers([layer]) },
      to: { path: inLayers(LAYERS.slice(i + 1)) },
    })),
    {
      name: 'not-in-a-layer',
      severity: 'error',
      comment: 'Every module under src/ belongs to a layer: classify it in LAYERS.',
      from: { path: SRC, pathNot: classified },
      to: {},
    },
    {
      // the two rules around this one only see modules with an import edge
      name: 'not-in-a-layer-orphan',
      severity: 'error',
      comment: 'Every module under src/ belongs to a layer, even one nothing imports: classify it in LAYERS.',
      from: { orphan: true, path: SRC, pathNot: [classified, '\\.d\\.ts$'] }, // declaration files carry no runtime code
      to: {},
    },
    {
      name: 'imports-a-module-in-no-layer',
      severity: 'error',
      comment: 'Every module under src/ belongs to a layer: classify it in LAYERS.',
      from: {},
      to: { path: SRC, pathNot: classified },
    },
  ],
  options: {
    // only the repo's own code: a cycle inside a library is not ours to fix
    doNotFollow: { path: 'node_modules' },
    // the tsconfig that includes src/: path aliases (@/...) resolve, so no edge is missed
    tsConfig: { fileName: 'tsconfig.json' },
    // false = the import graph that survives compilation; `import type` never cycles at runtime
    tsPreCompilationDeps: false,
    enhancedResolveOptions: { extensions: ['.ts', '.tsx', '.js', '.jsx', '.json'] },
  },
};
