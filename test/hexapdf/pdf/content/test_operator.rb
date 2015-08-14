# -*- encoding: utf-8 -*-

require 'test_helper'
require 'hexapdf/pdf/content/operator'
require 'hexapdf/pdf/content/processor'
require 'hexapdf/pdf/serializer'

describe HexaPDF::PDF::Content::Operator::BaseOperator do
  before do
    @op = HexaPDF::PDF::Content::Operator::BaseOperator.new('name')
  end

  it "takes a name on initialization and can return it" do
    assert_equal('name', @op.name)
    assert(@op.name.frozen?)
  end

  it "responds to invoke" do
    assert_respond_to(@op, :invoke)
  end

  it "can serialize any operator with its operands" do
    serializer = HexaPDF::PDF::Serializer.new
    assert_equal("5.0 5 /Name name\n", @op.serialize(serializer, 5.0, 5, :Name))
  end
end

describe HexaPDF::PDF::Content::Operator::NoArgumentOperator do
  it "provides a special serialize method" do
    op = HexaPDF::PDF::Content::Operator::NoArgumentOperator.new('name')
    assert_equal("name\n", op.serialize(nil))
  end
end

describe HexaPDF::PDF::Content::Operator::SingleNumericArgumentOperator do
  it "provides a special serialize method" do
    op = HexaPDF::PDF::Content::Operator::SingleNumericArgumentOperator.new('name')
    serializer = HexaPDF::PDF::Serializer.new
    assert_equal("5 name\n", op.serialize(serializer, 5))
    assert_equal("5.45 name\n", op.serialize(serializer, 5.45))
  end
end


module CommonOperatorTests
  extend Minitest::Spec::DSL

  before do
    resources = {}
    resources.define_singleton_method(:color_space) do |name|
      HexaPDF::PDF::GlobalConfiguration.constantize('color_space.map', name).new
    end
    @processor = HexaPDF::PDF::Content::Processor.new(resources)
    @serializer = HexaPDF::PDF::Serializer.new
  end

  # calls the method of the operator with the operands
  def call(method, *operands)
    HexaPDF::PDF::Content::Operator::DEFAULT_OPERATORS[@name].send(method, *operands)
  end

  # calls the invoke method on the operator
  def invoke(*operands)
    call(:invoke, @processor, *operands)
  end

  it "is associated with the correct operator name in the default mapping" do
    assert_equal(@name, call(:name).to_sym)
  end

  it "is not the base operator implementation" do
    refute_equal(HexaPDF::PDF::Content::Operator::BaseOperator, call(:class))
  end

  def assert_serialized(*operands)
    op = HexaPDF::PDF::Content::Operator::BaseOperator.new(@name.to_s)
    assert_equal(op.serialize(@serializer, *operands), call(:serialize, @serializer, *operands))
  end

end

def describe_operator(name, symbol, &block)
  klass_name = "HexaPDF::PDF::Content::Operator::#{name}"
  klass = describe(klass_name, &block)
  klass.send(:include, CommonOperatorTests)
  one_time_module = Module.new
  one_time_module.send(:define_method, :setup) do
    super()
    @name = symbol
  end
  one_time_module.send(:define_method, :test_class_name) do
    assert_equal(klass_name, call(:class).name)
  end
  klass.send(:include, one_time_module)
  klass
end


describe_operator :SaveGraphicsState, :q do
  it "saves the graphics state" do
    width = @processor.graphics_state.line_width
    invoke
    @processor.graphics_state.line_width = 10
    @processor.graphics_state.restore
    assert_equal(width, @processor.graphics_state.line_width)
  end
end

describe_operator :RestoreGraphicsState, :Q do
  it "restores the graphics state" do
    width = @processor.graphics_state.line_width
    @processor.graphics_state.save
    @processor.graphics_state.line_width = 10
    invoke
    assert_equal(width, @processor.graphics_state.line_width)
  end
end

describe_operator :ConcatenateMatrix, :cm do
  it "concatenates the ctm by pre-multiplication" do
    invoke(1, 2, 3, 4, 5, 6)
    invoke(6, 5, 4, 3, 2, 1)
    assert_equal(21, @processor.graphics_state.ctm.a)
    assert_equal(32, @processor.graphics_state.ctm.b)
    assert_equal(13, @processor.graphics_state.ctm.c)
    assert_equal(20, @processor.graphics_state.ctm.d)
    assert_equal(10, @processor.graphics_state.ctm.e)
    assert_equal(14, @processor.graphics_state.ctm.f)
  end

  it "serializes correctly" do
    assert_serialized(1, 2, 3, 4, 5, 6)
  end
end

describe_operator :SetLineWidth, :w do
  it "sets the line width" do
    invoke(10)
    assert_equal(10, @processor.graphics_state.line_width)
  end
end

describe_operator :SetLineCapStyle, :J do
  it "sets the line cap" do
    invoke(HexaPDF::PDF::Content::LineCapStyle::ROUND_CAP)
    assert_equal(HexaPDF::PDF::Content::LineCapStyle::ROUND_CAP,
                 @processor.graphics_state.line_cap_style)
  end
end

describe_operator :SetLineJoinStyle, :j do
  it "sets the line join" do
    invoke(HexaPDF::PDF::Content::LineJoinStyle::ROUND_JOIN)
    assert_equal(HexaPDF::PDF::Content::LineJoinStyle::ROUND_JOIN,
                 @processor.graphics_state.line_join_style)
  end
end

describe_operator :SetMiterLimit, :M do
  it "sets the miter limit" do
    invoke(100)
    assert_equal(100, @processor.graphics_state.miter_limit)
  end
end

describe_operator :SetLineDashPattern, :d do
  it "sets the line dash pattern" do
    invoke([3, 4], 5)
    assert_equal(HexaPDF::PDF::Content::LineDashPattern.new([3, 4], 5),
                 @processor.graphics_state.line_dash_pattern)
  end

  it "serializes correctly" do
    assert_serialized([3, 4], 5)
  end
end

describe_operator :SetRenderingIntent, :ri do
  it "sets the rendering intent" do
    invoke(HexaPDF::PDF::Content::RenderingIntent::SATURATION)
    assert_equal(HexaPDF::PDF::Content::RenderingIntent::SATURATION,
                 @processor.graphics_state.rendering_intent)
  end
end

describe_operator :SetGraphicsStateParameters, :gs do
  it "applies parameters from an ExtGState dictionary" do
    @processor.resources[:ExtGState] = {Name: {LW: 10, LC: 2, LJ: 2, ML: 2, D: [[3, 5], 2],
                                               RI: 2, SA: true, BM: :Multiply, CA: 0.5, ca: 0.5,
                                               AIS: true, TK: false}}
    invoke(:Name)
    assert_equal(10, @processor.graphics_state.line_width)
    assert_equal(2, @processor.graphics_state.line_cap_style)
    assert_equal(2, @processor.graphics_state.line_join_style)
    assert_equal(2, @processor.graphics_state.miter_limit)
    assert_equal(HexaPDF::PDF::Content::LineDashPattern.new([3, 5], 2),
                 @processor.graphics_state.line_dash_pattern)
    assert_equal(2, @processor.graphics_state.rendering_intent)
    assert(@processor.graphics_state.stroke_adjustment)
    assert_equal(:Multiply, @processor.graphics_state.blend_mode)
    assert_equal(0.5, @processor.graphics_state.stroking_alpha)
    assert_equal(0.5, @processor.graphics_state.non_stroking_alpha)
    assert(@processor.graphics_state.alpha_source)
    refute(@processor.graphics_state.text_state.knockout)
  end

  it "fails if the resources dictionary doesn't have an ExtGState entry" do
    assert_raises(HexaPDF::Error) { invoke(:Name) }
  end

  it "fails if the ExtGState resources doesn't have the specified dictionary" do
    @processor.resources[:ExtGState] = {}
    assert_raises(HexaPDF::Error) { invoke(:Name) }
  end

  it "serializes correctly" do
    assert_serialized(:Name)
  end
end

describe_operator :SetStrokingColorSpace, :CS do
  it "sets the stroking color space" do
    invoke(:DeviceRGB)
    assert_equal(@processor.resources.color_space(:DeviceRGB), @processor.graphics_state.stroking_color_space)
  end

  it "serializes correctly" do
    assert_serialized(:DeviceRGB)
  end
end

describe_operator :SetNonStrokingColorSpace, :cs do
  it "sets the non stroking color space" do
    invoke(:DeviceRGB)
    assert_equal(@processor.resources.color_space(:DeviceRGB),
                 @processor.graphics_state.non_stroking_color_space)
  end

  it "serializes correctly" do
    assert_serialized(:DeviceRGB)
  end
end

describe_operator :SetStrokingColor, :SC do
  it "sets the stroking color" do
    invoke(128)
    assert_equal(@processor.resources.color_space(:DeviceGray).color(128),
                 @processor.graphics_state.stroking_color)
  end

  it "serializes correctly" do
    assert_serialized(128, 129, 130)
  end
end

describe_operator :SetNonStrokingColor, :sc do
  it "sets the non stroking color" do
    invoke(128)
    assert_equal(@processor.resources.color_space(:DeviceGray).color(128),
                 @processor.graphics_state.non_stroking_color)
  end

  it "serializes correctly" do
    assert_serialized(128, 129, 130)
  end
end

describe_operator :SetDeviceGrayStrokingColor, :G do
  it "sets the DeviceGray stroking color" do
    invoke(128)
    assert_equal(@processor.resources.color_space(:DeviceGray).color(128),
                 @processor.graphics_state.stroking_color)
  end
end

describe_operator :SetDeviceGrayNonStrokingColor, :g do
  it "sets the DeviceGray non stroking color" do
    invoke(128)
    assert_equal(@processor.resources.color_space(:DeviceGray).color(128),
                 @processor.graphics_state.non_stroking_color)
  end
end

describe_operator :SetDeviceRGBStrokingColor, :RG do
  it "sets the DeviceRGB stroking color" do
    invoke(128, 0, 128)
    assert_equal(@processor.resources.color_space(:DeviceRGB).color(128, 0, 128),
                 @processor.graphics_state.stroking_color)
  end

  it "serializes correctly" do
    assert_serialized(128, 129, 130)
  end
end

describe_operator :SetDeviceRGBNonStrokingColor, :rg do
  it "sets the DeviceRGB non stroking color" do
    invoke(128, 0, 128)
    assert_equal(@processor.resources.color_space(:DeviceRGB).color(128, 0, 128),
                 @processor.graphics_state.non_stroking_color)
  end

  it "serializes correctly" do
    assert_serialized(128, 129, 130)
  end
end

describe_operator :SetDeviceCMYKStrokingColor, :K do
  it "sets the DeviceCMYK stroking color" do
    invoke(128, 0, 128, 128)
    assert_equal(@processor.resources.color_space(:DeviceCMYK).color(128, 0, 128, 128),
                 @processor.graphics_state.stroking_color)
  end

  it "serializes correctly" do
    assert_serialized(128, 129, 130, 131)
  end
end

describe_operator :SetDeviceCMYKNonStrokingColor, :k do
  it "sets the DeviceCMYK non stroking color" do
    invoke(128, 0, 128, 128)
    assert_equal(@processor.resources.color_space(:DeviceCMYK).color(128, 0, 128, 128),
                 @processor.graphics_state.non_stroking_color)
  end

  it "serializes correctly" do
    assert_serialized(128, 129, 130, 131)
  end
end

describe_operator :MoveTo, :m do
  it "changes the graphics object to path" do
    refute(@processor.in_path?)
    invoke(128, 0)
    assert(@processor.in_path?)
  end

  it "serializes correctly" do
    assert_serialized(1.54, 1.78)
  end
end

describe_operator :AppendRectangle, :re do
  it "changes the graphics object to path" do
    refute(@processor.in_path?)
    invoke(128, 0, 10, 10)
    assert(@processor.in_path?)
  end

  it "serializes correctly" do
    assert_serialized(10, 11, 1.54, 1.78)
  end
end

describe_operator :LineTo, :l do
  it "serializes correctly" do
    assert_serialized(1.54, 1.78)
  end
end

describe_operator :CurveTo, :c do
  it "serializes correctly" do
    assert_serialized(1.54, 1.78, 2, 3, 5, 6)
  end
end

describe_operator :CurveToNoFirstControlPoint, :v do
  it "serializes correctly" do
    assert_serialized(2, 3, 5, 6)
  end
end

describe_operator :CurveToNoSecondControlPoint, :y do
  it "serializes correctly" do
    assert_serialized(2, 3, 5, 6)
  end
end

[:S, :s, :f, :F, 'f*'.intern, :B, 'B*'.intern, :b, 'b*'.intern, :n].each do |sym|
  describe_operator :EndPath, sym do
    it "changes the graphics object to none" do
      @processor.graphics_object = :path
      invoke
      refute(@processor.in_path?)
    end
  end
end

[:W, 'W*'.intern].each do |sym|
  describe_operator :ClipPath, sym do
    it "changes the graphics object to clipping_path for clip path operations" do
      invoke
      assert_equal(:clipping_path, @processor.graphics_object)
    end
  end
end

describe_operator :InlineImage, :BI do
  it "serializes correctly" do
    assert_equal("BI\n/Name 5 /OP 6 ID\nsome dataEI\n",
                 call(:serialize, @serializer, {Name: 5, OP: 6}, 'some data'))
  end
end

describe_operator :SetCharacterSpacing, :Tc do
  it "modifies the character spacing in the text state" do
    invoke(127)
    assert_equal(127, @processor.graphics_state.text_state.character_spacing)
  end
end

describe_operator :SetWordSpacing, :Tw do
  it "modifies the word spacing in the text state" do
    invoke(127)
    assert_equal(127, @processor.graphics_state.text_state.word_spacing)
  end
end

describe_operator :SetHorizontalScaling, :Tz do
  it "modifies the horizontal scaling parameter in the text state" do
    invoke(127)
    assert_equal(127, @processor.graphics_state.text_state.horizontal_scaling)
  end
end

describe_operator :SetLeading, :TL do
  it "modifies the leading parameter in the text state" do
    invoke(127)
    assert_equal(127, @processor.graphics_state.text_state.leading)
  end
end

describe_operator :SetFontAndSize, :Tf do
  it "serializes correctly" do
    assert_serialized(:Font, 1.78)
  end
end

describe_operator :SetTextRenderingMode, :Tr do
  it "modifies the text rendering mode in the text state" do
    invoke(127)
    assert_equal(127, @processor.graphics_state.text_state.rendering_mode)
  end
end

describe_operator :SetTextRise, :Ts do
  it "modifies the text rise in the text state" do
    invoke(127)
    assert_equal(127, @processor.graphics_state.text_state.rise)
  end
end

describe_operator :BeginText, :BT do
  it "changes the graphics object to text" do
    @processor.graphics_object = :none
    invoke
    assert_equal(:text, @processor.graphics_object)
  end
end

describe_operator :EndText, :ET do
  it "changes the graphics object to :none" do
    @processor.graphics_object = :text
    invoke
    assert_equal(:none, @processor.graphics_object)
  end
end

describe_operator :MoveText, :Td do
  it "serializes correctly" do
    assert_serialized(1.54, 1.78)
  end
end

describe_operator :MoveTextAndSetLeading, :TD do
  it "invokes the TL and Td operators" do
    tl = Minitest::Mock.new
    tl.expect(:invoke, nil, [@processor, -1.78])
    @processor.operators[:TL] = tl
    td = Minitest::Mock.new
    td.expect(:invoke, nil, [@processor, 1.56, 1.78])
    @processor.operators[:Td] = td

    invoke(1.56, 1.78)
    tl.verify
    td.verify
  end

  it "serializes correctly" do
    assert_serialized(1.54, 1.78)
  end
end

describe_operator :SetTextMatrix, :Tm do
  it "serializes correctly" do
    assert_serialized(1, 2, 3, 4, 5, 6)
  end
end

describe_operator :MoveTextNextLine, :'T*' do
  it "invokes the Td operator" do
    td = Minitest::Mock.new
    td.expect(:invoke, nil, [@processor, 0, -1.78])
    @processor.operators[:Td] = td

    @processor.graphics_state.text_state.leading = 1.78
    invoke
    td.verify
  end
end

describe_operator :ShowText, :Tj do
  it "serializes correctly" do
    assert_serialized("Some Text")
  end
end

describe_operator :MoveTextNextLineAndShowText, :"'" do
  it "invokes the T* and Tj operators" do
    text = "Some text"

    tstar = Minitest::Mock.new
    tstar.expect(:invoke, nil, [@processor])
    @processor.operators[:'T*'] = tstar
    tj = Minitest::Mock.new
    tj.expect(:invoke, nil, [@processor, text])
    @processor.operators[:Tj] = tj

    invoke(text)
    tstar.verify
    tj.verify
  end

  it "serializes correctly" do
    assert_serialized("Some Text")
  end
end

describe_operator :SetSpacingMoveTextNextLineAndShowText, :'"' do
  it "invokes the Tw, Tc and ' operators" do
    word_spacing = 10
    char_spacing = 15
    text = "Some text"

    tw = Minitest::Mock.new
    tw.expect(:invoke, nil, [@processor, word_spacing])
    @processor.operators[:Tw] = tw
    tc = Minitest::Mock.new
    tc.expect(:invoke, nil, [@processor, char_spacing])
    @processor.operators[:Tc] = tc
    tapos = Minitest::Mock.new
    tapos.expect(:invoke, nil, [@processor, text])
    @processor.operators[:"'"] = tapos

    invoke(word_spacing, char_spacing, text)
    tw.verify
    tc.verify
    tapos.verify
  end

  it "serializes correctly" do
    assert_serialized(10, 15, "Some Text")
  end
end

describe_operator :ShowTextWithPositioning, :TJ do
  it "serializes correctly" do
    assert_serialized(["Some Text", 15, "other text", 20, "final text"])
  end
end
