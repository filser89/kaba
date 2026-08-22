#!/usr/bin/env ruby
# frozen_string_literal: true

# Emits a structural digest for every test example block in the given spec files:
# one "FILE<TAB>START_LINE<TAB>SHA256" line per example call, consumed by
# snapshot-tests.sh capture (joined onto RSpec examples by file + line).
#
# The serialization walks node types and literal values only — never source
# locations or comments — so formatting-only edits hash identically while any
# structural or literal change flips the digest. Loop-generated examples share
# their single `it` node and therefore one digest (a change flags the group).

require "prism"
require "digest"

EXAMPLE_METHODS = %i[it specify example scenario].freeze

def serialize(node, out)
  out << node.type.to_s << "("
  case node
  when Prism::StringNode, Prism::SymbolNode then out << node.unescaped.dump
  when Prism::IntegerNode, Prism::FloatNode then out << node.value.to_s
  when Prism::CallNode                      then out << node.name.to_s
  when Prism::ConstantReadNode              then out << node.name.to_s
  when Prism::LocalVariableReadNode, Prism::LocalVariableTargetNode,
       Prism::InstanceVariableReadNode, Prism::InstanceVariableWriteNode,
       Prism::RequiredParameterNode
    out << node.name.to_s
  end
  node.compact_child_nodes.each do |child|
    out << ","
    serialize(child, out)
  end
  out << ")"
end

def example_nodes(node, acc = [])
  acc << node if node.is_a?(Prism::CallNode) && EXAMPLE_METHODS.include?(node.name)
  node.compact_child_nodes.each { |child| example_nodes(child, acc) }
  acc
end

abort "usage: digest_examples.rb FILE..." if ARGV.empty?

ARGV.each do |path|
  result = Prism.parse_file(path)
  abort "ERROR: parse failure in #{path}" unless result.success?
  example_nodes(result.value).each do |node|
    buffer = +""
    serialize(node, buffer)
    puts "#{path}\t#{node.location.start_line}\t#{Digest::SHA256.hexdigest(buffer)}"
  end
end
