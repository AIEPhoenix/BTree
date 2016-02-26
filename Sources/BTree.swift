//
//  BTree.swift
//  BTree
//
//  Created by Károly Lőrentey on 2016-02-19.
//  Copyright © 2015–2016 Károly Lőrentey.
//

/// B-trees are search trees that provide an ordered key-value store with excellent performance characteristics.
public struct BTree<Key: Comparable, Payload> {
    public typealias Element = (Key, Payload)
    internal typealias Node = BTreeNode<Key, Payload>

    internal var root: Node

    internal init(_ root: Node) {
        self.root = root
    }

    /// Initialize a new b-tree with no elements.
    ///
    /// - Parameter order: The maximum number of children for tree nodes.
    public init(order: Int = Node.defaultOrder) {
        self.root = Node(order: order)
    }

    /// The order of this tree, i.e., the maximum number of children for tree nodes.
    public var order: Int { return root.order }
    /// The depth of this tree. Depth starts at 0 for a tree that has a single root node.
    public var depth: Int { return root.depth }
}

//MAKE: Uniquing

public extension BTree {
    internal var isUnique: Bool {
        mutating get {
            return isUniquelyReferenced(&root)
        }
    }

    internal mutating func makeUnique() {
        guard !isUnique else { return }
        root = root.clone()
    }
}

//MARK: SequenceType

extension BTree: SequenceType {
    public typealias Generator = BTreeGenerator<Key, Payload>

    /// Returns true iff this tree has no elements.
    public var isEmpty: Bool { return root.count == 0 }

    /// Returns a generator over the elements of this b-tree. Elements are sorted by key.
    public func generate() -> Generator {
        return Generator(BTreeStrongPath(root: root, position: 0))
    }

    /// Returns a generator starting at a specific index.
    public func generate(from index: Index) -> Generator {
        index.state.expectRoot(root)
        return Generator(BTreeStrongPath(root: root, slots: index.state.slots))
    }

    /// Returns a generator starting at a specific position.
    public func generate(fromPosition position: Int) -> Generator {
        return Generator(BTreeStrongPath(root: root, position: position))
    }

    /// Returns a generator starting at the element with the specified key.
    /// If the tree contains no such element, the generator is positioned at the first element with a larger key.
    /// If there are multiple elements with the same key, `selector` indicates which matching element to find.
    public func generate(from key: Key, choosing selector: BTreeKeySelector = .Any) -> Generator {
        return Generator(BTreeStrongPath(root: root, key: key, choosing: selector))
    }

    /// Call `body` on each element in self in the same order as a for-in loop.
    public func forEach(@noescape body: (Element) throws -> ()) rethrows {
        try root.forEach(body)
    }

    /// A version of `forEach` that allows `body` to interrupt iteration by returning `false`.
    ///
    /// - Returns: `true` iff `body` returned true for all elements in the tree.
    public func forEach(@noescape body: (Element) throws -> Bool) rethrows -> Bool {
        return try root.forEach(body)
    }
}

//MARK: CollectionType

extension BTree: CollectionType {
    public typealias Index = BTreeIndex<Key, Payload>
    public typealias SubSequence = BTree<Key, Payload>

    /// The index of the first element of this tree. Elements are sorted by key.
    public var startIndex: Index {
        return Index(BTreeWeakPath(root: root, position: 0))
    }

    /// The index after the last element of this tree. (Equals `startIndex` when the tree is empty.)
    public var endIndex: Index {
        return Index(BTreeWeakPath(root: root, position: count))
    }

    /// The number of elements in this tree.
    public var count: Int {
        return root.count
    }

    /// Returns the element at `index`.
    ///
    /// - Complexity: O(1)
    public subscript(index: Index) -> Element {
        get {
            index.state.expectRoot(self.root)
            return index.state.element
        }
    }

    /// Returns a tree consisting of elements in the specified range of indexes.
    ///
    /// - Complexity: O(log(`count`))
    public subscript(range: Range<Index>) -> BTree<Key, Payload> {
        get {
            return subtree(with: range)
        }
    }
}

//MARK: Lookups

/// When the tree contains multiple elements with the same key, you can use a key selector to specify
/// that you want to use the first or last matching element, or that you don't care which element you get.
/// (The latter is sometimes faster.)
public enum BTreeKeySelector {
    /// Look for the first element that matches the key, or insert a new element before existing matches.
    case First
    /// Look for the last element that matches the key, or insert a new element after existing matches.
    case Last
    /// Accept any element that matches the key. This is sometimes faster, because the search may stop before reaching
    /// a leaf node.
    case Any
}

public extension BTree {
    /// Returns the element at `position`.
    ///
    /// - Requires: `position >= 0 && position < count`
    /// - Complexity: O(log(`count`))
    @warn_unused_result
    public func elementAtPosition(position: Int) -> Element {
        precondition(position >= 0 && position < count)
        var position = position
        var node = root
        while !node.isLeaf {
            let slot = node.slotOfPosition(position)
            if slot.match {
                return node.elements[slot.index]
            }
            let child = node.children[slot.index]
            position -= slot.position - child.count
            node = child
        }
        return node.elements[position]
    }

    /// Returns the payload of an element of this tree with the specified key, or `nil` if there is no such element.
    /// If there are multiple elements with the same key, `selector` indicates which matching element to find.
    ///
    /// - Complexity: O(log(`count`))
    @warn_unused_result
    public func payloadOf(key: Key, choosing selector: BTreeKeySelector = .Any) -> Payload? {
        switch selector {
        case .Any:
            var node = root
            while true {
                let slot = node.slotOf(key, choosing: .First)
                if let m = slot.match {
                    return node.elements[m].1
                }
                if node.isLeaf {
                    break
                }
                node = node.children[slot.descend]
            }
            return nil
        case .First, .Last:
            var node = root
            var lastmatch: Payload? = nil
            while true {
                let slot = node.slotOf(key, choosing: selector)
                if let m = slot.match {
                    lastmatch = node.elements[m].1
                }
                if node.isLeaf {
                    break
                }
                node = node.children[slot.descend]
            }
            return lastmatch
        }
    }

    /// Returns an index to an element in this tree with the specified key, or `nil` if there is no such element.
    /// If there are multiple elements with the same key, `selector` indicates which matching element to find.
    ///
    /// - Complexity: O(log(`count`))
    @warn_unused_result
    public func indexOf(key: Key, choosing selector: BTreeKeySelector = .Any) -> Index? {
        let path = BTreeWeakPath(root: root, key: key, choosing: selector)
        guard !path.isAtEnd && path.key == key else { return nil }
        return Index(path)
    }

    /// Returns the position of the first element in this tree with the specified key, or `nil` if there is no such element.
    /// If there are multiple elements with the same key, `selector` indicates which matching element to find.
    ///
    /// - Complexity: O(log(`count`))
    @warn_unused_result
    public func positionOf(key: Key, choosing selector: BTreeKeySelector = .Any) -> Int? {
        var node = root
        var position = 0
        var match: Int? = nil
        while !node.isLeaf {
            let slot = node.slotOf(key, choosing: selector)
            let child = node.children[slot.descend]
            if let m = slot.match {
                let p = node.positionOfSlot(m)
                match = position + p
                position += p - (m == slot.descend ? node.children[m].count : 0)
            }
            else {
                position += node.positionOfSlot(slot.descend) - child.count
            }
            node = child
        }
        let slot = node.slotOf(key, choosing: selector)
        if let m = slot.match {
            return position + m
        }
        return match
    }

    /// Returns the position of the element at `index`.
    ///
    /// - Complexity: O(log(`count`))
    @warn_unused_result
    public func positionOfIndex(index: Index) -> Int {
        index.state.expectRoot(root)
        return index.state.position
    }

    /// Returns the index of the element at `position`.
    ///
    /// - Requires: `position >= 0 && position <= count`
    /// - Complexity: O(log(`count`))
    @warn_unused_result
    public func indexOfPosition(position: Int) -> Index {
        return Index(BTreeWeakPath(root: root, position: position))
    }
}


//MARK: Editing

extension BTree {
    /// Edit the tree at a path that is to be discovered on the way down, ensuring that all nodes on the path are 
    /// uniquely held by this tree. 
    /// This is a simple (but not easy, alas) interface that allows implementing basic editing operations using 
    /// recursion without adding a separate method on `BTreeNode` for each operation.
    ///
    /// Editing is split into two phases: the descent phase and the ascend phase. 
    ///
    /// - During descent, the `descend` closure is called repeatedly to get the next child slot to drill down into.
    ///   When the closure returns `nil`, the phase stops and the ascend phase begins.
    /// - During ascend, the `ascend` closure is called for each node for which `descend` returned non-nil, in reverse
    ///   order.
    ///
    /// - Parameter descend: A closure that, when given a node, returns the child slot toward which the editing should
    ///   continue descending, or `nil` if the descent should stop. The closure may set outside references to the 
    ///   node it gets, and may modify the node as it likes; however, it shouldn't modify anything in the tree outside
    ///   the node's subtree, and it should not set outside references to the node's descendants.
    /// - Parameter ascend: A closure that processes a step of ascending back towards the root. It receives a parent node
    ///   and the child slot from which this step is ascending. The closure may set outside references to the
    ///   node it gets, and may modify the subtree as it likes; however, it shouldn't modify anything in the tree outside
    ///   the node's subtree.
    internal mutating func edit(@noescape descend descend: Node -> Int?, @noescape ascend: (Node, Int) -> Void) {
        makeUnique()
        root.edit(descend: descend, ascend: ascend)
    }
}

//MARK: Insertion

extension BTree {
    /// Insert the specified element into the tree at `position`.
    ///
    /// - Requires: The key of the supplied element does not violate the b-tree's ordering requirement.
    ///   (This is only verified in non-optimized builds.)
    /// - Note: When you need to perform multiple modifications on the same tree,
    ///   `BTreeCursor` provides an alternative interface that's often more efficient.
    /// - Complexity: O(log(`count`))
    public mutating func insert(element: Element, at position: Int) {
        precondition(position >= 0 && position <= count)
        makeUnique()
        var pos = count - position
        var splinter: BTreeSplinter<Key, Payload>? = nil
        var element = element
        edit(
            descend: { node in
                let slot = node.slotOfPosition(node.count - pos)
                assert(slot.index == 0 || node.elements[slot.index - 1].0 <= element.0)
                assert(slot.index == node.elements.count || node.elements[slot.index].0 >= element.0)
                if !slot.match {
                    // Continue descending.
                    pos -= node.count - slot.position
                    return slot.index
                }
                if node.isLeaf {
                    // Found the insertion point. Insert, then start ascending.
                    node.insert(element, inSlot: slot.index)
                    if node.isTooLarge {
                        splinter = node.split()
                    }
                    return nil
                }
                // For internal nodes, put the new element in place of the old at the same position,
                // then continue descending toward the next position, inserting the old element.
                element = node.setElementInSlot(slot.index, to: element)
                pos = node.children[slot.index + 1].count
                return slot.index + 1
            },
            ascend: { node, slot in
                node.count += 1
                if let s = splinter {
                    node.insert(s, inSlot: slot)
                    splinter = node.isTooLarge ? node.split() : nil
                }
            }
        )
        if let s = splinter {
            root = Node(left: root, separator: s.separator, right: s.node)
        }
    }

    /// Set the payload at `position`, and return the payload originally stored there.
    ///
    /// - Requires: `position < count`
    /// - Note: When you need to perform multiple modifications on the same tree,
    ///   `BTreeCursor` provides an alternative interface that's often more efficient.
    /// - Complexity: O(log(`count`))
    public mutating func setPayloadAt(position: Int, to payload: Payload) -> Payload {
        precondition(position >= 0 && position < count)
        makeUnique()
        var pos = count - position
        var old: Payload? = nil
        edit(
            descend: { node in
                let slot = node.slotOfPosition(node.count - pos)
                if !slot.match {
                    // Continue descending.
                    pos -= node.count - slot.position
                    return slot.index
                }
                old = node.elements[slot.index].1
                node.elements[slot.index].1 = payload
                return nil
            },
            ascend: { node, slot in
            }
        )
        return old!
    }

    /// Insert `element` into the tree as a new element.
    /// If the tree already contains elements with the same key, `selector` specifies where to put the new element.
    ///
    /// - Note: When you need to perform multiple modifications on the same tree,
    ///   `BTreeCursor` provides an alternative interface that's often more efficient.
    /// - Complexity: O(log(`count`))
    public mutating func insert(element: Element, at selector: BTreeKeySelector = .Any) {
        makeUnique()
        let selector = selector == .Any ? .Last : selector
        var splinter: BTreeSplinter<Key, Payload>? = nil
        edit(
            descend: { node in
                let slot = node.slotOf(element.0, choosing: selector)
                if !node.isLeaf {
                    return slot.descend
                }
                node.insert(element, inSlot: slot.descend)
                if node.isTooLarge {
                    splinter = node.split()
                }
                return nil
            },
            ascend: { node, slot in
                node.count += 1
                if let s = splinter {
                    node.insert(s, inSlot: slot)
                    splinter = node.isTooLarge ? node.split() : nil
                }
            }
        )
        if let s = splinter {
            root = Node(left: root, separator: s.separator, right: s.node)
        }
    }

    /// Insert `element` into the tree, replacing an element with the same key if there is one.
    /// If the tree already contains multiple elements with the same key, `selector` specifies which one to replace.
    ///
    /// - Note: When you need to perform multiple modifications on the same tree,
    ///   `BTreeCursor` provides an alternative interface that's often more efficient.
    /// - Complexity: O(log(`count`))
    public mutating func insertOrReplace(element: Element, at selector: BTreeKeySelector = .Any) -> Payload? {
        makeUnique()
        var old: Payload? = nil
        var match: (node: Node, slot: Int)? = nil
        var splinter: BTreeSplinter<Key, Payload>? = nil
        edit(
            descend: { node in
                let slot = node.slotOf(element.0, choosing: selector)
                if node.isLeaf {
                    if let m = slot.match {
                        // We found the element we want to replace.
                        old = node.setElementInSlot(m, to: element).1
                        match = nil
                    }
                    else if old == nil && match == nil {
                        // The tree contains no matching elements; insert a new one.
                        node.insert(element, inSlot: slot.descend)
                        if node.isTooLarge {
                            splinter = node.split()
                        }
                    }
                    return nil
                }
                if let m = slot.match {
                    if selector == .Any {
                        // When we don't care about which element to replace, we stop the descent at the first match.
                        old = node.setElementInSlot(m, to: element).1
                        return nil
                    }
                    // Otherwise remember this match and replace it during ascend if it's the last one.
                    match = (node, m)
                }
                return slot.descend
            },
            ascend: { node, slot in
                if let m = match {
                    // We're looking for the node that contains the last match.
                    if m.node === node {
                        // Found it; replace the matching element and cancel the search.
                        old = node.setElementInSlot(m.slot, to: element).1
                        match = nil
                    }
                }
                else if old == nil {
                    // We're ascending from an insertion.
                    node.count += 1
                    if let s = splinter {
                        node.insert(s, inSlot: slot)
                        splinter = node.isTooLarge ? node.split() : nil
                    }
                }
            }
        )
        if let s = splinter {
            root = Node(left: root, separator: s.separator, right: s.node)
        }
        return old
    }
}

//MARK: Removal

extension BTree {
    /// Remove and return the element at the specified position.
    ///
    /// - Note: When you need to perform multiple modifications on the same tree,
    ///   `BTreeCursor` provides an alternative interface that's often more efficient.
    /// - Complexity: O(log(`count`))
    public mutating func removeAt(position: Int) -> Element {
        precondition(position >= 0 && position < count)
        makeUnique()
        var pos = count - position
        var matching: (node: Node, slot: Int)? = nil
        var old: Element? = nil
        edit(
            descend: { node in
                let slot = node.slotOfPosition(node.count - pos)
                if !slot.match {
                    // No match yet; continue descending.
                    assert(!node.isLeaf)
                    pos -= node.count - slot.position
                    return slot.index
                }
                if node.isLeaf {
                    // The position we're looking for is in a leaf node; we can remove it directly.
                    old = node.removeSlot(slot.index)
                    return nil
                }
                // When the position happens to fall into an internal node, remember the match and continue
                // removing the next position (which is guaranteed to be in a leaf node).
                // We'll replace the removed element with this one during the ascend.
                matching = (node, slot.index)
                pos = node.children[slot.index + 1].count
                return slot.index + 1
            },
            ascend: { node, slot in
                node.count -= 1
                if let m = matching where m.node === node {
                    // We've removed the element at the next position; put it back in place of the
                    // element we actually want to remove.
                    old = node.setElementInSlot(m.slot, to: old!)
                    matching = nil
                }
                if node.children[slot].isTooSmall {
                    node.fixDeficiency(slot)
                }
            }
        )
        if root.children.count == 1 {
            assert(root.elements.count == 0)
            root = root.children[0]
        }
        return old!
    }

    /// Remove an element with the specified key, if it exists.
    /// If there are multiple elements with the same key, `selector` indicates which matching element to remove.
    ///
    /// - Returns: The payload of the removed element, or `nil` if there was no element with `key` in the tree.
    /// - Note: When you need to perform multiple modifications on the same tree,
    ///   `BTreeCursor` provides an alternative interface that's often more efficient.
    /// - Complexity: O(log(`count`))
    public mutating func remove(key: Key, at selector: BTreeKeySelector = .Any) -> Payload? {
        makeUnique()
        var old: Element? = nil
        var matching: (node: Node, slot: Int)? = nil
        edit(
            descend: { node in
                let slot = node.slotOf(key, choosing: selector)
                if node.isLeaf {
                    if let m = slot.match {
                        old = node.removeSlot(m)
                        matching = nil
                    }
                    else if matching != nil {
                        old = node.removeSlot(slot.descend == node.elements.count ? slot.descend - 1 : slot.descend)
                    }
                    return nil
                }
                if let m = slot.match {
                    matching = (node, m)
                }
                return slot.descend
            },
            ascend: { node, slot in
                if let o = old {
                    node.count -= 1
                    if let m = matching where m.node === node {
                        old = node.setElementInSlot(m.slot, to: o)
                        matching = nil
                    }
                    if node.children[slot].isTooSmall {
                        node.fixDeficiency(slot)
                    }
                }
            }
        )
        if root.children.count == 1 {
            assert(root.elements.count == 0)
            root = root.children[0]
        }
        return old?.1
    }
}

//MARK: Subtree extraction

extension BTree {
    /// Returns a subtree containing the initial `maxLength` elements in this tree.
    ///
    /// If `maxLength` exceeds `self.count`, the result contains all the elements of `self`.
    ///
    /// - Complexity: O(log(`count`))
    public func prefix(maxLength: Int) -> BTree {
        precondition(maxLength >= 0)
        if maxLength == 0 {
            return BTree(order: order)
        }
        if maxLength >= count {
            return self
        }
        return BTreeStrongPath(root: root, position: maxLength).prefix()
    }

    /// Returns a subtree containing all but the last `n` elements.
    ///
    /// - Complexity: O(log(`count`))
    public func dropLast(n: Int) -> BTree {
        precondition(n >= 0)
        return prefix(max(0, count - n))
    }

    /// Returns a subtree containing all elements before the specified index.
    ///
    /// - Complexity: O(log(`count`))
    public func prefixUpTo(end: Index) -> BTree {
        end.state.expectRoot(root)
        if end.state.isAtEnd {
            return self
        }
        return end.state.prefix()
    }

    /// Returns a subtree containing all elements whose key is less than `key`.
    ///
    /// - Complexity: O(log(`count`))
    public func prefixUpTo(end: Key) -> BTree {
        let path = BTreeStrongPath(root: root, key: end, choosing: .First)
        if path.isAtEnd {
            return self
        }
        return path.prefix()
    }

    /// Returns a subtree containing all elements at or before the specified index.
    ///
    /// - Complexity: O(log(`count`))
    public func prefixThrough(stop: Index) -> BTree {
        return prefixUpTo(stop.successor())
    }

    /// Returns a subtree containing all elements whose key is less than or equal to `key`.
    ///
    /// - Complexity: O(log(`count`))
    public func prefixThrough(stop: Key) -> BTree {
        var path = BTreeStrongPath(root: root, key: stop, choosing: .Last)
        if !path.isAtEnd && path.key == stop {
            path.moveForward()
        }
        if path.isAtEnd {
            return self
        }
        return path.prefix()
    }

    /// Returns a tree containing the final `maxLength` elements in this tree.
    ///
    /// If `maxLength` exceeds `self.count`, the result contains all the elements of `self`.
    ///
    /// - Complexity: O(log(`count`))
    public func suffix(maxLength: Int) -> BTree {
        precondition(maxLength >= 0)
        if maxLength == 0 {
            return BTree(order: order)
        }
        if maxLength >= count {
            return self
        }
        return BTreeStrongPath(root: root, position: count - maxLength - 1).suffix()
    }

    /// Returns a subtree containing all but the first `n` elements.
    ///
    /// - Complexity: O(log(`count`))
    public func dropFirst(n: Int) -> BTree {
        precondition(n >= 0)
        return suffix(max(0, count - n))
    }

    /// Returns a subtree containing all elements at or after the specified index.
    ///
    /// - Complexity: O(log(`count`))
    public func suffixFrom(start: Index) -> BTree {
        start.state.expectRoot(root)
        if start.state.position == 0 {
            return self
        }
        return start.predecessor().state.suffix()
    }

    /// Returns a subtree containing all elements whose key is greater than or equal to `key`.
    ///
    /// - Complexity: O(log(`count`))
    public func suffixFrom(start: Key) -> BTree {
        var path = BTreeStrongPath(root: root, key: start, choosing: .First)
        if path.isAtStart {
            return self
        }
        path.moveBackward()
        return path.suffix()
    }

    /// Return a subtree consisting of elements in the specified range of indexes.
    ///
    /// - Complexity: O(log(`count`))
    @warn_unused_result
    public func subtree(with range: Range<Index>) -> BTree<Key, Payload> {
        range.startIndex.state.expectRoot(root)
        range.endIndex.state.expectRoot(root)
        let start = range.startIndex.state.position
        let end = range.endIndex.state.position
        precondition(0 <= start && start <= end && end <= self.count)
        if start == end {
            return BTree(order: self.order)
        }
        if start == 0 {
            return prefixUpTo(range.endIndex)
        }
        return suffixFrom(range.startIndex).prefix(end - start)
    }

    /// Return a subtree consisting of elements in the specified range of positions.
    ///
    /// - Complexity: O(log(`count`))
    @warn_unused_result
    public func subtree(with positions: Range<Int>) -> BTree<Key, Payload> {
        precondition(positions.startIndex >= 0 && positions.endIndex <= count)
        if positions.count == 0 {
            return BTree(order: order)
        }
        return dropFirst(positions.startIndex).prefix(positions.count)
    }

    /// Return a subtree consisting of all elements with keys greater than or equal to `start` but less than `end`.
    ///
    /// - Complexity: O(log(`count`))
    @warn_unused_result
    public func subtree(from start: Key, to end: Key) -> BTree<Key, Payload> {
        precondition(start <= end)
        return suffixFrom(start).prefixUpTo(end)
    }

    /// Return a submap consisting of all elements with keys greater than or equal to `start` but less than or equal to `end`.
    ///
    /// - Complexity: O(log(`count`))
    @warn_unused_result
    public func subtree(from start: Key, through stop: Key) -> BTree<Key, Payload> {
        precondition(start <= stop)
        return suffixFrom(start).prefixThrough(stop)
    }
}

//MARK: Bulk loading

extension BTree {
    /// Create a new b-tree from elements of a sequence sorted by key.
    ///
    /// - Parameter sortedElements: A sequence of arbitrary length, sorted by key.
    /// - Parameter order: The desired b-tree order. If not specified (recommended), the default order is used.
    /// - Parameter fillFactor: The desired fill factor in each node of the new tree. Must be between 0.5 and 1.0.
    ///      If not specified, a value of 1.0 is used, i.e., nodes will be loaded with as many elements as possible.
    /// - Complexity: O(count)
    /// - SeeAlso: `init(elements:order:fillFactor:)` for a (slower) unsorted variant.
    public init<S: SequenceType where S.Generator.Element == Element>(sortedElements elements: S, order: Int = Node.defaultOrder, fillFactor: Double = 1) {
        precondition(order > 1)
        precondition(fillFactor >= 0.5 && fillFactor <= 1)
        let keysPerNode = Int(fillFactor * Double(order - 1) + 0.5)
        assert(keysPerNode >= (order - 1) / 2 && keysPerNode <= order - 1)

        var generator = elements.generate()

        // This bulk loading algorithm works growing a line of perfectly loaded saplings, in order of decreasing depth,
        // with a separator element between each of them.
        // In each step, a new separator and a new 0-depth, fully loaded node is loaded from the sequence as a new seedling.
        // The seedling is then appended to or recursively merged into the list of saplings.
        // Finally, at the end of the sequence, the final list of saplings plus the last partial seedling is joined
        // into a single tree, which becomes the root.

        var saplings: [Node] = []
        var separators: [Element] = []

        var lastKey: Key? = nil
        var seedling = Node(order: order)
        outer: while true {
            // Create new separator.
            if saplings.count > 0 {
                guard let element = generator.next() else { break outer }
                precondition(lastKey <= element.0)
                lastKey = element.0
                separators.append(element)
            }
            // Load new seedling.
            while seedling.elements.count < keysPerNode {
                guard let element = generator.next() else { break outer }
                precondition(lastKey <= element.0)
                lastKey = element.0
                seedling.elements.append(element)
                seedling.count += 1
            }
            // Append seedling into saplings, combining the last few seedlings when possible.
            while !saplings.isEmpty && seedling.elements.count == keysPerNode {
                let sapling = saplings.last!
                assert(sapling.depth >= seedling.depth)
                if sapling.depth == seedling.depth + 1 && sapling.elements.count < keysPerNode {
                    // Graft current seedling under the last sapling, as a new child branch.
                    saplings.removeLast()
                    let separator = separators.removeLast()
                    sapling.elements.append(separator)
                    sapling.children.append(seedling)
                    sapling.count += seedling.count + 1
                    seedling = sapling
                }
                else if sapling.depth == seedling.depth && sapling.elements.count == keysPerNode {
                    // We have two full nodes; add them as two branches of a new, deeper seedling.
                    saplings.removeLast()
                    let separator = separators.removeLast()
                    seedling = Node(left: sapling, separator: separator, right: seedling)
                }
                else {
                    break
                }
            }
            saplings.append(seedling)
            seedling = Node(order: order)
        }

        // Merge saplings and seedling into a single tree.
        if separators.count == saplings.count - 1 {
            assert(seedling.count == 0)
            self.root = saplings.removeLast()
        }
        else {
            self.root = seedling
        }
        assert(separators.count == saplings.count)
        while !saplings.isEmpty {
            self.root = Node.join(left: saplings.removeLast(), separator: separators.removeLast(), right: self.root)
        }
    }

    /// Create a new b-tree from elements of an unsorted sequence.
    ///
    /// - Parameter elements: An unsorted sequence of arbitrary length.
    /// - Parameter order: The desired b-tree order. If not specified (recommended), the default order is used.
    /// - Parameter fillFactor: The desired fill factor in each node of the new tree. Must be between 0.5 and 1.0.
    ///      If not specified, a value of 1.0 is used, i.e., nodes will be loaded with as many elements as possible.
    /// - Complexity: O(count * log(`count`))
    /// - SeeAlso: `init(sortedElements:order:fillFactor:)` for a (faster) variant that can be used if the sequence is already sorted.
    public init<S: SequenceType where S.Generator.Element == Element>(elements: S, order: Int = Node.defaultOrder, fillFactor: Double = 1) {
        self.init(sortedElements: elements.sort { $0.0 < $1.0 }, order: order, fillFactor: fillFactor)
    }
}
