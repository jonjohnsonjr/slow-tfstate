# tfstate

This repo demonstrates why it's impossible to manage a lot of resources.

Simplifying greatly, the overall loop for an `apply` looks something like this:

```go
func main() {
    prev := refresh()

    nodes := plan()

    for _, node := range nodes {
        state := apply(node)

        if json.Marshal(normalize(prev)) != json.Marshal(normalize(state)) {
            writeState(json.Marshal(state))
        }

        prev = state
    }
}
```

Every `PostStateUpdate` will compare the current state to the previous state and write it out to `terraform.tfstate` if they differ.

For small amounts of state, this has a negligible impact, but as the size of that state grows, this starts to dominate execution time.

## Accidentally Quadratic

The size of most `terraform.tfstate` files will grow ~linearly with the number of resources being managed, assuming that each resource adds some constant amount of state to the file.

The number of times we have to call `PostStateUpdate` will also grow with the number of resources being managed, as we have to update state for each resource.

Assuming a single resource takes a constant amount of time to `json.Marshal`, we can estimate the total time we spend in `json.Marshal` for `x` resources as:

$`f(x) = \int{3x} = \frac{3x^2}{2}`$

## Possible Solutions

### Do the same thing but faster

We spend about half of this time indenting JSON (https://github.com/opentofu/opentofu/pull/397).
That's a bit silly, especially because we throw away the output for 2 of the 3 marshaled states.
We could probably also adopt https://pkg.go.dev/github.com/go-json-experiment/json and try to do faster JSON encoding.

Unfortunately, this doesn't really work; it will speed things up by some scalar, but we're still looking at quadratic performance.
We will very quickly hit the same thing at a slightly higher scale.

### Snapshot periodically

The Filesystem statemgr implementation seems to be implemented [incorrectly](https://github.com/opentofu/opentofu/blob/656ab5a8beb8716939e3c6178c95647fb683264d/internal/states/statemgr/filesystem.go#L123-L124), possibly due to assumptions around performance.
Actually fixing this implementation to use [`PersistState`](https://github.com/opentofu/opentofu/blob/656ab5a8beb8716939e3c6178c95647fb683264d/internal/states/statemgr/filesystem.go#L227-L231) for persisting state would cause [this logic](https://github.com/opentofu/opentofu/blob/656ab5a8beb8716939e3c6178c95647fb683264d/internal/backend/local/hook_state.go#L81-L89) to only `PersistState` periodically rather than constantly.
There is a [hardcoded 20s `PersistInterval`](https://github.com/opentofu/opentofu/blob/656ab5a8beb8716939e3c6178c95647fb683264d/internal/backend/local/backend_apply.go#L85) that would give us at least 20s of forward progress between calls to `PersistState`, so we'd never completely grind to a halt.

I will open a PR to see if opentofu would be interested in this kind of change.

### Reinvent State

The way state is handled monolithically like this is not great for performance.
Instead of serializing the whole thing to a single JSON object, we could also shard state across multiple files.

Even more interesting would be to use something like sqlite for managing state so it can be queried.

This seems like a lot more work, so probably indefinitely infeasible...
