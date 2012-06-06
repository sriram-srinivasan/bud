## Bud Issues
There are some problems with the way Bud currently handles joins. A  few of these issues are common to JOL and C4 as well.

* Doesn't use a table's primary index where it can.
* No join ordering. Even if it were there, the scanner architecture doesn't allow scans to be done in a controlled way. Which forces the downstream join to cache one half of the stream.
* Scanner is not context-sensitive. For example, in computing (\(a \bowtie \delta b\)), a scan of  \(a\) is wasted if \(\delta b\) is empty. Of course, right now, a scan isn't really wasted because it populates one half of the pipelined join's buffer, but see next ...
* Pipelined symmetric hash joins are not a good fit because we have a mixed streaming and persistence model, and often end up duplicating information already present in the join's source, or that ends up in a sink collection.  For joins that involve index lookups or do cross products, redoing the join on the fly is not much different than iterating on the memoized join result.  The latter has the problem that materialized state is tough to manage incrementally for negation, and if not managed incrementally (as is the case with Bud now), it is a big performance drain to invalidate the whole materialized state if anything is negated upstream. 
* No special treatment for singletons and timers and tick-local scratches. Timers often have no storage, no delta, and tick-local scratches (input interfaces and others that are reliably cleared at every tick have no storage, and often no delta)
* No sharing of indexes across joins.  e.g. kvs creates identical indexes on kv_state.key for each join with kv_get, kv_del and kv_put
* Unnecessary tupling.   While computing \((a \bowtie b \bowtie c)\), the  \((a \bowtie b)\) subtree produces \([a,b]\) tuples, which are then unpacked to form \([a,b,c]\) tuples. Further, a join's output is often to a user-defined collection, so memoization of the join state and the extra tupling is a waste of space and time.
* Selections aren't pushed in

## Proposed Solution
Let \(a' = (a \cup \delta a)\).  In Bud, \(a\) refers to the table.storage, \(\delta a\) refers to table.delta.

First fix join order so that adjacent pairs are in an equijoin relationship where possible. Additionally, keep timers, singletons and deltas (in that order)  on the left (on the outer side). We'll create left-leaning joins: \(a \bowtie b \bowtie c = (a \bowtie b) \bowtie c \).  For any join node, the left is either a join or a relation, the right is always a relation.

Given a bloom rule "\(d \Leftarrow a \bowtie b \bowtie c\)", the logical dataflow graph for naive evaluation is as follows.

[[naive.svg]]

push and insert are the output and input "ports" at every edge. The cardinality of join's push port is equal to the cardinality of the join. A transform node encapsulates all user code attached to the join, as well as any shim required to repackage for the target node. Oval nodes represent computation; they do not maintain state.

For delta (or semi-naive) evaluation, we delta-rewrite the graph:

\(\delta(X \bowtie y) = (\delta(X) \bowtie y') \cup  (X \bowtie \delta y) \).  X is either a join or a relation, as mentioned above.

The first level of transformation looks like this:
[[semi-naive.svg"]]

Note that the transform node (the original join node's target) does the union, because its insert(a,b,c) is called from both upstream nodes.

Now for the second level of transformation: 
[[semi-naive2.svg]]

Node 4 is an intermediate node that receives a stream of (a,b) pairs (via insert(a,b)) from upstream nodes (corresponding to \(\delta(a*b)\)). That node's insert joins each \((a,b)\) pair with \(c'\) (either nested loop or hash-lookup). Since this effort must not go to waste, the upstream nodes are told to scan only if \(c'\) is non-empty. This check is called a //scan-guard//, and is used to implement the context-sensitivity mentioned earlier; this join requests a scan of \(a\) and \(b\) only if  \(c'\) is non-empty. Likewise, \(\delta c\) is checked for non-emptyness on the right hand side.

The leaf join nodes at the top do both scanning and joining. 

!!!Optimizations

A scratch is logically emptied at every tick, which means there's no storage. However a scratch that monotonically depends upon a table will rederive its contents every single tick, so emptying the scratch and rebuilding it is wasteful. We can identify scratches that //must// be emptied (input interfaces, channels, timers); if these are involved in a join, these yield simpler delta-rewrites since their "storage" is always empty, and they only have deltas.

Consider the kvs rule, \(kvget\_response \Leftarrow kv\_get * kv\_state\).   \(kv\_get\) is an input scratch, so the delta-rewrite of the join can be simplified to \(\delta kv\_get \bowtie kv\_state'\).  The other half,  \(kv\_get \bowtie \delta kv\_state\) is empty becayse \(kv\_get\) is empted at every tick;  we need only worry about deltas.
!!! Todo
#  Conditional expressions
#  Sharing with outerjoins and anti joins.
#  Self-join and renaming

!!!!! Conditional expressions
Assume a join condition in DNF form \(J = (\alpha_1 \wedge \beta_1 \wedge \alpha\beta_1 \wedge \gamma_1) \vee (\alpha_2 \wedge \beta_2 \wedge \gamma_2)\), where \(\alpha, \beta, \gamma\) represent conditions related purely to \(a, b, c\) respectively, and pairs refer to combinations (some of which may be equijoin conditions). The expression \((\alpha_1 \wedge \beta_1 \wedge \alpha\beta_1) \vee (\alpha_2 \wedge \beta_2)\) is evaluated by the leaf nodes on top (\(J\) stripped of \(\gamma\)'s). The disadvantage of this componentized architecture is that the expression \(J\) will have to be reevaluated in its entirety (because of the disjunction) at the node 4. However, if there were no disjunctions, only the \(\gamma\)'s need to be evaluated. 

