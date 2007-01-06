#
# bio/util/restrction_enzyme/range/sequence_range.rb - 
#
# Author::    Trevor Wennblom  <mailto:trevor@corevx.com>
# Copyright:: Copyright (c) 2005-2007 Midwinter Laboratories, LLC (http://midwinterlabs.com)
# License::   Distributes under the same terms as Ruby
#
#  $Id: sequence_range.rb,v 1.3 2007/01/06 05:35:04 trevor Exp $
#
require 'pathname'
libpath = Pathname.new(File.join(File.dirname(__FILE__), ['..'] * 5, 'lib')).cleanpath.to_s
$:.unshift(libpath) unless $:.include?(libpath)

require 'bio/util/restriction_enzyme/range/cut_ranges'
require 'bio/util/restriction_enzyme/range/horizontal_cut_range'
require 'bio/util/restriction_enzyme/range/vertical_cut_range'
require 'bio/util/restriction_enzyme/range/sequence_range/calculated_cuts'
require 'bio/util/restriction_enzyme/range/sequence_range/fragments'
require 'bio/util/restriction_enzyme/range/sequence_range/fragment'
require 'bio'

module Bio; end
class Bio::RestrictionEnzyme
class Range
#
# bio/util/restrction_enzyme/range/sequence_range.rb - 
#
# Author::    Trevor Wennblom  <mailto:trevor@corevx.com>
# Copyright:: Copyright (c) 2005-2007 Midwinter Laboratories, LLC (http://midwinterlabs.com)
# License::   Distributes under the same terms as Ruby
class SequenceRange

  attr_reader :p_left, :p_right
  attr_reader :c_left, :c_right

  attr_reader :left, :right
  attr_reader :size
  attr_reader :cut_ranges

  def initialize( p_left = nil, p_right = nil, c_left = nil, c_right = nil )
    @__fragments_current = false
    raise ArgumentError if p_left == nil and c_left == nil
    raise ArgumentError if p_right == nil and c_right == nil
    (raise ArgumentError unless p_left <= p_right) unless p_left == nil or p_right == nil
    (raise ArgumentError unless c_left <= c_right) unless c_left == nil or c_right == nil

    @p_left  = p_left
    @p_right = p_right
    @c_left  = c_left
    @c_right = c_right

    tmp = [p_left, c_left]
    tmp.delete(nil)
    @left = tmp.sort.first

    tmp = [p_right, c_right]
    tmp.delete(nil)
    @right = tmp.sort.last

    @size = (@right - @left) + 1 unless @left == nil or @right == nil

    @cut_ranges = CutRanges.new
  end

  # Cut occurs immediately after the index supplied.
  # For example, a cut at '0' would mean a cut occurs between 0 and 1.
  def add_cut_range( p_cut_left=nil, p_cut_right=nil, c_cut_left=nil, c_cut_right=nil )
    @__fragments_current = false

    if p_cut_left.kind_of? CutRange
      @cut_ranges << p_cut_left
    else
      (raise IndexError unless p_cut_left >= @left and p_cut_left <= @right) unless p_cut_left == nil
      (raise IndexError unless p_cut_right >= @left and p_cut_right <= @right) unless p_cut_right == nil
      (raise IndexError unless c_cut_left >= @left and c_cut_left <= @right) unless c_cut_left == nil
      (raise IndexError unless c_cut_right >= @left and c_cut_right <= @right) unless c_cut_right == nil

      @cut_ranges << VerticalCutRange.new( p_cut_left, p_cut_right, c_cut_left, c_cut_right )
    end
  end

  def add_cut_ranges(*cut_ranges)
    cut_ranges.flatten!
    cut_ranges.each do |cut_range|
      raise TypeError, "Not of type CutRange" unless cut_range.kind_of? CutRange
      self.add_cut_range( cut_range )
    end
  end

  def add_horizontal_cut_range( left, right=left )
    @__fragments_current = false
    @cut_ranges << HorizontalCutRange.new( left, right )
  end
  
  Bin = Struct.new(:c, :p)

  def fragments
    return @__fragments if @__fragments_current == true
    @__fragments_current = true
    
    num_txt = '0123456789'
    num_txt_repeat = (num_txt * ( @size / num_txt.size.to_f ).ceil)[0..@size-1]
    fragments = Fragments.new(num_txt_repeat, num_txt_repeat)

    cc = Bio::RestrictionEnzyme::Range::SequenceRange::CalculatedCuts.new(@size)
    cc.add_cuts_from_cut_ranges(@cut_ranges)
    cc.remove_incomplete_cuts
    
    create_bins(cc).sort.each { |k, bin| fragments << Fragment.new( bin.p, bin.c ) }
    @__fragments = fragments
    return fragments
  end
  
  #########
  protected
  #########
  
  # Example:
  #   cc = Bio::RestrictionEnzyme::Range::SequenceRange::CalculatedCuts.new(@size)
  #   cc.add_cuts_from_cut_ranges(@cut_ranges)
  #   cc.remove_incomplete_cuts
  #   bins = create_bins(cc)
  # 
  # Example return value:
  #   {0=>#<struct Bio::RestrictionEnzyme::Range::SequenceRange::Bin c=[0, 1], p=[0]>,
  #    2=>#<struct Bio::RestrictionEnzyme::Range::SequenceRange::Bin c=[], p=[1, 2]>,
  #    3=>#<struct Bio::RestrictionEnzyme::Range::SequenceRange::Bin c=[2, 3], p=[]>,
  #    4=>#<struct Bio::RestrictionEnzyme::Range::SequenceRange::Bin c=[4, 5], p=[3, 4, 5]>}
  #
  # ---
  # *Arguments*
  # * +cc+: Bio::RestrictionEnzyme::Range::SequenceRange::CalculatedCuts
  # *Returns*:: +Hash+ Keys are unique, values are Bio::RestrictionEnzyme::Range::SequenceRange::Bin objects filled with indexes of the sequence locations they represent.
  def create_bins(cc)
    p_cut = cc.vc_primary
    c_cut = cc.vc_complement
    h_cut = cc.hc_between_strands
    
    if @circular
      # NOTE
      # if it's circular we should start at the beginning of a cut for orientation
      # scan for it, hack off the first set of hcuts and move them to the back
  
      unique_id = 0
    else
      p_cut.unshift(-1) unless p_cut.include?(-1)
      c_cut.unshift(-1) unless c_cut.include?(-1)
      unique_id = -1
    end

    p_bin_id = c_bin_id = unique_id
    bins = {}
    setup_new_bin(bins, unique_id)

    -1.upto(@size-1) do |idx| # NOTE - circular, for the future - should '-1' be replace with 'unique_id'?
      
      # if bin_ids are out of sync but the strands are attached
      if (p_bin_id != c_bin_id) and !h_cut.include?(idx)
        min_id, max_id = [p_bin_id, c_bin_id].sort
        bins.delete(max_id)
        p_bin_id = c_bin_id = min_id
      end

      bins[ p_bin_id ].p << idx
      bins[ c_bin_id ].c << idx
      
      if p_cut.include? idx
        p_bin_id = (unique_id += 1)
        setup_new_bin(bins, p_bin_id)
      end

      if c_cut.include? idx             # repetition
        c_bin_id = (unique_id += 1)     # repetition
        setup_new_bin(bins, c_bin_id)   # repetition
      end                               # repetition
       
    end
  
    # Bin "-1" is an easy way to indicate the start of a strand just in case
    # there is a horizontal cut at position 0
    bins.delete(-1) unless @circular
    bins
  end
  
  # Modifies bins in place by creating a new element with key bin_id and
  # initializing the bin.
  def setup_new_bin(bins, bin_id)
    bins[ bin_id ] = Bin.new
    bins[ bin_id ].p = []
    bins[ bin_id ].c = []
  end
  
end # SequenceRange
end # Range
end # Bio::RestrictionEnzyme