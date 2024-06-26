#' Functions to generate alternate representations of graphs
#'
#' These functions are meant to be passed into [morph()] to create a temporary
#' alternate representation of the input graph. They are thus not meant to be
#' called directly. See below for detail of each morpher.
#'
#' @param graph A `tbl_graph`
#'
#' @param ... Arguments to pass on to [filter()], [group_by()], or the cluster
#' algorithm (see [igraph::cluster_walktrap()], [igraph::cluster_leading_eigen()],
#' and [igraph::cluster_edge_betweenness()])
#'
#' @param subset_by,split_by Whether to create subgraphs based on nodes or edges
#'
#' @return A list of `tbl_graph`s
#'
#' @rdname morphers
#' @name morphers
#'
#' @examples
#' # Compute only on a subgraph of every even node
#' create_notable('meredith') %>%
#'   morph(to_subgraph, seq_len(graph_order()) %% 2 == 0) %>%
#'   mutate(neighbour_count = centrality_degree()) %>%
#'   unmorph()
NULL

#' @describeIn morphers Convert a graph to its line graph. When unmorphing node
#' data will be merged back into the original edge data. Edge data will be
#' ignored.
#' @importFrom igraph make_line_graph
#' @export
to_linegraph <- function(graph) {
  line_graph <- as_tbl_graph(make_line_graph(graph))
  line_graph <- mutate(activate(line_graph, 'nodes'), .tidygraph_edge_index = E(graph)$.tidygraph_edge_index)
  list(
    line_graph = line_graph
  )
}
#' @describeIn morphers Convert a graph to a single subgraph. `...` is evaluated
#' in the same manner as `filter`. When unmorphing all data in the subgraph
#' will get merged back.
#' @importFrom igraph induced_subgraph subgraph.edges
#' @export
to_subgraph <- function(graph, ..., subset_by = NULL) {
  if (is.null(subset_by)) {
    subset_by <- active(graph)
    cli::cli_inform('Subsetting by {subset_by}')
  }
  ind <- as_tibble(graph, active = subset_by)
  ind <- mutate(ind, .tidygraph_index = seq_len(n()))
  ind <- filter(ind, ...)
  ind <- ind$.tidygraph_index
  subset <- switch(
    subset_by,
    nodes = induced_subgraph(graph, ind),
    edges = subgraph.edges(graph, ind, delete.vertices = FALSE)
  )
  list(
    subgraph = as_tbl_graph(subset)
  )
}
#' @describeIn morphers Convert a graph to a single component containing the specified node
#' @param node The center of the neighborhood for `to_local_neighborhood()` and
#' the node to that should be included in the component for `to_subcomponent()`
#' @importFrom igraph components
#' @export
to_subcomponent <- function(graph, node) {
  node <- eval_tidy(enquo(node), as_tibble(graph, 'nodes'))
  node <- as_node_ind(node, graph)
  if (length(node) != 1) cli::cli_abort('{.arg node} must identify a single node in the graph')
  component_membership <- components(graph)$membership == components(graph)$membership[node]
  to_subgraph(graph, component_membership, subset_by = 'nodes')
}
#' @describeIn morphers Convert a graph into a list of separate subgraphs. `...`
#' is evaluated in the same manner as `group_by`. When unmorphing all data in
#' the subgraphs will get merged back, but in the case of `split_by = 'edges'`
#' only the first instance of node data will be used (as the same node can be
#' present in multiple subgraphs).
#' @importFrom igraph induced_subgraph subgraph.edges
#' @importFrom stats setNames
#' @importFrom dplyr group_rows
#' @export
to_split <- function(graph, ..., split_by = NULL) {
  if (is.null(split_by)) {
    split_by <- active(graph)
    cli::cli_inform('Splitting by {split_by}')
  }
  ind <- as_tibble(graph, active = split_by)
  ind <- group_by(ind, ...)
  splits <- lapply(group_rows(ind), function(i) {
    g <- switch(
      split_by,
      nodes = induced_subgraph(graph, i),
      edges = subgraph.edges(graph, i)
    )
    as_tbl_graph(g)
  })
  split_names <- group_keys(ind)
  split_names <- lapply(names(split_names), function(n) {
    paste(n, split_names[[n]], sep = ': ')
  })
  split_names <- do.call(paste, modifyList(unname(split_names), list(sep = ', ')))
  setNames(splits, split_names)
}
#' @describeIn morphers Split a graph into its separate components. When
#' unmorphing all data in the subgraphs will get merged back.
#' @param type The type of component to split into. Either `'weak'` or `'strong'`
#' @param min_order The minimum order (number of vertices) of the component.
#' Components below this will not be created
#' @importFrom igraph decompose
#' @export
to_components <- function(graph, type = 'weak', min_order = 1) {
  graphs <- decompose(graph, mode = type)
  graphs <- lapply(graphs, as_tbl_graph)
  graphs
}
#' @describeIn morphers Create a new graph only consisting of it's largest
#' component. If multiple largest components exists, the one with containing the
#' node with the lowest index is chosen.
#' @importFrom igraph largest_component
#' @export
to_largest_component <- function(graph, type = 'weak') {
  list(
    largest_component = as_tbl_graph(largest_component(graph, mode = type))
  )
}
#' @describeIn morphers Convert a graph into its complement. When unmorphing
#' only node data will get merged back.
#' @param loops Should loops be included. Defaults to `FALSE`
#' @importFrom igraph complementer
#' @export
to_complement <- function(graph, loops = FALSE) {
  complement <- complementer(graph, loops = loops)
  list(
    complement = as_tbl_graph(complement)
  )
}
#' @describeIn morphers Convert a graph into the local neighborhood around a
#' single node. When unmorphing all data will be merged back.
#' @param order The radius of the neighborhood
#' @param mode How should edges be followed? `'out'` only follows outbound
#' edges, `'in'` only follows inbound edges, and `'all'` follows all edges. This
#' parameter is ignored for undirected graphs.
#' @importFrom igraph make_ego_graph
#' @export
to_local_neighborhood <- function(graph, node, order = 1, mode = 'all') {
  node <- eval_tidy(enquo(node), as_tibble(graph, 'nodes'))
  node <- as_node_ind(node, graph)
  ego <- make_ego_graph(graph, order = order, nodes = node, mode = mode)
  list(
    neighborhood = as_tbl_graph(ego[[1]])
  )
}
#' @describeIn morphers Convert a graph into its dominator tree based on a
#' specific root. When unmorphing only node data will get merged back.
#' @param root The root of the tree
#' @importFrom igraph dominator_tree
#' @export
to_dominator_tree <- function(graph, root, mode = 'out') {
  root <- eval_tidy(enquo(root), as_tibble(graph, 'nodes'))
  root <- as_node_ind(root, graph)
  dom <- dominator_tree(graph, root = root, mode = mode)
  list(
    dominator_tree = as_tbl_graph(dom$domtree)
  )
}
#' @describeIn morphers Convert a graph into its minimum spanning tree/forest.
#' When unmorphing all data will get merged back.
#' @param weights Optional edge weights for the calculations
#' @importFrom igraph mst
#' @importFrom rlang enquo eval_tidy
#' @export
to_minimum_spanning_tree <- function(graph, weights = NULL) {
  weights <- eval_tidy(enquo(weights), as_tibble(graph, 'edges'))
  algorithm <- if (is.null(weights)) 'unweighted' else 'prim'
  mst <- mst(graph, weights = weights, algorithm = algorithm)
  list(
    mst = as_tbl_graph(mst)
  )
}
#' @describeIn morphers Convert a graph into a random spanning tree/forest. When
#' unmorphing all data will get merged back
#' @importFrom igraph subgraph.edges sample_spanning_tree
#' @export
to_random_spanning_tree <- function(graph) {
  list(
    spanning_tree = as_tbl_graph(subgraph.edges(graph, sample_spanning_tree(graph)))
  )
}
#' @describeIn morphers Limit a graph to the shortest path between two nodes.
#' When unmorphing all data is merged back.
#' @param from,to The start and end node of the path
#' @importFrom igraph shortest_paths
#' @importFrom rlang enquo eval_tidy
#' @export
to_shortest_path <- function(graph, from, to, mode = 'out', weights = NULL) {
  nodes <- as_tibble(graph, 'nodes')
  from <- eval_tidy(enquo(from), nodes)
  from <- as_node_ind(from, graph)
  to <- eval_tidy(enquo(to), nodes)
  to <- as_node_ind(to, graph)
  weights <- eval_tidy(enquo(weights), as_tibble(graph, active = 'edges')) %||% NA
  path <- shortest_paths(graph, from = from, to = to, mode = mode, weights = weights, output = 'both')
  short_path <- slice(activate(graph, 'edges'), as.integer(path$epath[[1]]))
  short_path <- slice(activate(short_path, 'nodes'), as.integer(path$vpath[[1]]))
  list(
    shortest_path = short_path
  )
}
#' @describeIn morphers Convert a graph into a breath-first search tree based on
#' a specific root. When unmorphing only node data is merged back.
#' @param unreachable Should the search jump to a node in a new component when
#' stuck.
#' @importFrom igraph bfs
#' @export
to_bfs_tree <- function(graph, root, mode = 'out', unreachable = FALSE) {
  root <- eval_tidy(enquo(root), as_tibble(graph, 'nodes'))
  root <- as_node_ind(root, graph)
  search <- bfs(graph, root, mode = mode, unreachable = unreachable, father = TRUE)
  bfs_graph <- search_to_graph(graph, search)
  list(
    bfs = bfs_graph
  )
}
#' @describeIn morphers Convert a graph into a depth-first search tree based on
#' a specific root. When unmorphing only node data is merged back.
#' @importFrom igraph bfs
#' @export
to_dfs_tree <- function(graph, root, mode = 'out', unreachable = FALSE) {
  root <- eval_tidy(enquo(root), as_tibble(graph, 'nodes'))
  root <- as_node_ind(root, graph)
  search <- dfs(graph, root, mode = mode, unreachable = unreachable, father = TRUE)
  dfs_graph <- search_to_graph(graph, search)
  list(
    dfs = dfs_graph
  )
}
#' @describeIn morphers Collapse parallel edges and remove loops in a graph.
#' When unmorphing all data will get merged back
#' @param remove_multiples Should edges that run between the same nodes be
#' reduced to one
#' @param remove_loops Should edges that start and end at the same node be removed
#' @importFrom igraph simplify
#' @export
to_simple <- function(graph, remove_multiples = TRUE, remove_loops = TRUE) {
  edges <- as_tibble(graph, active = 'edges')
  graph <- set_edge_attributes(graph, edges[, '.tidygraph_edge_index', drop = FALSE])
  edges$.tidygraph_edge_index <- NULL
  simple <- as_tbl_graph(simplify(graph, remove.multiple = remove_multiples, remove.loops = remove_loops, edge.attr.comb = list))
  new_edges <- as_tibble(simple, active = 'edges')
  new_edges$.orig_data <- lapply(new_edges$.tidygraph_edge_index, function(i) edges[i, , drop = FALSE])
  simple <- set_edge_attributes(simple, new_edges)
  list(
    simple = simple
  )
}
#' @describeIn morphers Expand weighted links into multiple edges. Each link with
#' a weight equal to a natural number will be split into multiple edges.
#' @param weights The name of the column containing the weights.
#' @importFrom igraph is_directed
#' @importFrom rlang ensym
#' @export
to_multi <- function(graph, weights = "weight") {
  weights <- rlang::ensym(weights)
  edges <- as_tibble(graph, active = 'edges')
  graph <- set_edge_attributes(graph, edges[, '.tidygraph_edge_index', drop = FALSE])
  
  weights_col <- rlang::as_string(weights)
  
  if (!weights_col %in% colnames(edges)) {
    stop("The specified weight column does not exist in the edges.")
  }
  
  # Ensure weights are natural numbers
  if (any(edges[[weights_col]] <= 0) | any(edges[[weights_col]] != floor(edges[[weights_col]]))) {
    stop("All weights must be natural numbers (positive integers).")
  }
  
  # Repeat edges according to their weight
  expanded_edges <- tidyr::uncount(edges, weights = !!weights)
  edges$.tidygraph_edge_index <- NULL
  expanded_edges$.orig_data <- lapply(expanded_edges$.tidygraph_edge_index, function(i) edges[i, , drop = FALSE])
  
  # Create a new graph with expanded edges
  multi_edge_graph <- tbl_graph(nodes = as_tibble(graph, active = 'nodes'),
                                edges = expanded_edges, directed = is_directed(graph))
  multi_edge_graph <- set_edge_attributes(multi_edge_graph, expanded_edges)
  
  list(
    multi_edge_graph = multi_edge_graph
  )
}
#' @describeIn morphers Combine multiple nodes into one. `...`
#' is evaluated in the same manner as `group_by`. When unmorphing all
#' data will get merged back.
#' @param remove_multiples Should edges that run between the same nodes be
#' reduced to one
#' @param remove_loops Should edges that start and end at the same node be removed
#' @importFrom tidyr nest_legacy
#' @importFrom igraph contract
#' @export
to_contracted <- function(graph, ..., remove_multiples = TRUE, remove_loops = TRUE) {
  nodes <- as_tibble(graph, active = 'nodes')
  nodes <- group_by(nodes, ...)
  ind <- group_indices(nodes)
  ind <- match(ind, unique(ind))
  contracted <- as_tbl_graph(contract(graph, ind, vertex.attr.comb = 'ignore'))
  nodes <- nest_legacy(nodes, .key = '.orig_data')
  ind <- lapply(nodes$.orig_data, `[[`, '.tidygraph_node_index')
  nodes$.orig_data <- lapply(nodes$.orig_data, function(x) {x$.tidygraph_node_index <- NULL; x})
  nodes$.tidygraph_node_index <- ind
  contracted <- set_node_attributes(contracted, nodes)
  if (remove_multiples | remove_loops) {
    contracted <- to_simple(contracted, remove_multiples = remove_multiples, remove_loops = remove_loops)[[1]]
  }
  list(
    contracted = contracted
  )
}
#' @describeIn morphers Unfold a graph to a tree or forest starting from
#' multiple roots (or one), potentially duplicating nodes and edges.
#' @importFrom igraph unfold_tree
#' @export
to_unfolded_tree <- function(graph, root, mode = 'out') {
  root <- eval_tidy(enquo(root), as_tibble(graph, 'nodes'))
  roots <- as_node_ind(root, graph)
  unfolded <- unfold_tree(graph, mode, roots)
  tree <- as_tbl_graph(unfolded$tree)
  tree <- set_node_attributes(tree, as_tibble(graph, 'nodes')[unfolded$vertex_index, ])
  tree <- set_edge_attributes(tree, as_tibble(graph, 'edges'))
  list(
    tree = tree
  )
}
#' @describeIn morphers Make a graph directed in the direction given by from and
#' to
#' @export
to_directed <- function(graph) {
  tbl_graph(as_tibble(graph, active = 'nodes'),
            as_tibble(graph, active = 'edges'),
            directed = TRUE) %gr_attr% graph
}
#' @describeIn morphers Make a graph undirected
#' @export
to_undirected <- function(graph) {
  tbl_graph(as_tibble(graph, active = 'nodes'),
            as_tibble(graph, active = 'edges'),
            directed = FALSE) %gr_attr% graph
}
#' @describeIn morphers Convert a graph into a hierarchical clustering based on a grouping
#' @param method The clustering method to use. Either `'walktrap'`, `'leading_eigen'`, or `'edge_betweenness'`
#' @importFrom igraph cluster_walktrap cluster_leading_eigen cluster_edge_betweenness gorder vertex_attr
#' @importFrom stats as.dendrogram
#' @importFrom rlang .data enquo eval_tidy
#' @export
to_hierarchical_clusters <- function(graph, method = 'walktrap', weights = NULL, ...) {
  weights <- enquo(weights)
  weights <- eval_tidy(weights, .E()) %||% NA
  hierarchy <- switch(
    method,
    walktrap = cluster_walktrap(graph, weights = weights, ...),
    leading_eigen = cluster_leading_eigen(graph, weights = weights, ...),
    edge_betweenness = cluster_edge_betweenness(graph, weights = weights, ...)
  )
  hierarchy <- as_tbl_graph(as.dendrogram(hierarchy))
  label <- vertex_attr(hierarchy, "label")
  orig_label <- vertex_attr(graph, "name") %||% as.character(seq_len(gorder(graph)))
  hierarchy <- mutate(hierarchy, .tidygraph_node_index = match(label, orig_label),
                      label = NULL)
  hierarchy <- left_join(hierarchy, as_tibble(graph, active = 'nodes'),
                         by = c('.tidygraph_node_index' = '.tidygraph_node_index'))
  hierarchy %gr_attr% graph
}

# HELPERS -----------------------------------------------------------------

search_to_graph <- function(graph, search) {
  nodes <- as_tibble(graph, active = 'nodes')
  edges <- tibble(from = search$father, to = seq_len(nrow(nodes)))
  edges <- edges[!is.na(edges$from), , drop = FALSE]
  tbl_graph(nodes, edges)
}
