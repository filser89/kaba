#!/usr/bin/env ruby
# frozen_string_literal: true

# Deletes test examples skip-marked for removal by a completed feature's test session:
#
#   it "original description", skip: "REMOVED by 004-feature-name" do ... end
#
# Prism-based: examples are located via the parser's exact source ranges — no regex
# block-guessing. Invoked by cleanup-tests.sh, which self-verifies the result (suite
# green, example count reduced by exactly the deleted total) and rolls back on mismatch.
#
# Usage: ruby delete_removed_examples.rb [--count-only] FILE...
# Prints one "<count>\t<path>" line per file. --count-only reports without editing.

require "prism"

MARKER_PREFIX = "REMOVED by "
EXAMPLE_METHODS = %i[it specify example scenario].freeze

count_only = !ARGV.delete("--count-only").nil?
abort "usage: delete_removed_examples.rb [--count-only] FILE..." if ARGV.empty?

def marked_example_nodes(node, acc = [])
  if node.is_a?(Prism::CallNode) && EXAMPLE_METHODS.include?(node.name)
    args = node.arguments&.arguments || []
    keywords = args.find { |a| a.is_a?(Prism::KeywordHashNode) }
    marked = keywords&.elements&.any? do |el|
      el.is_a?(Prism::AssocNode) &&
        el.key.is_a?(Prism::SymbolNode) && el.key.unescaped == "skip" &&
        el.value.is_a?(Prism::StringNode) && el.value.unescaped.start_with?(MARKER_PREFIX)
    end
    acc << node if marked
  end
  node.compact_child_nodes.each { |child| marked_example_nodes(child, acc) }
  acc
end

total = 0
ARGV.each do |path|
  result = Prism.parse_file(path)
  abort "ERROR: parse failure in #{path}" unless result.success?

  nodes = marked_example_nodes(result.value)
  total += nodes.length
  puts "#{nodes.length}\t#{path}"
  next if count_only || nodes.empty?

  lines = File.readlines(path)
  # Delete whole-line ranges, deepest-first so earlier offsets stay valid. When the
  # deleted block was surrounded by blank lines on both sides, also drop the trailing
  # one so no double blank line is left behind (local, never a global squeeze — blank
  # runs inside other tests' heredocs must not be touched).
  nodes.map { |n| [n.location.start_line, n.location.end_line] }
       .sort_by { |start_line, _| -start_line }
       .each do |start_line, end_line|
    blank_before = start_line >= 2 && lines[start_line - 2].strip.empty?
    blank_after = !lines[end_line].nil? && lines[end_line].strip.empty?
    delete_end = blank_before && blank_after ? end_line + 1 : end_line
    lines.slice!((start_line - 1)...delete_end)
  end
  File.write(path, lines.join)
end

warn "deleted total: #{total}" unless count_only
