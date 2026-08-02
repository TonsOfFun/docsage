require "test_helper"

class CitationValidatorTest < ActiveSupport::TestCase
  test "verifies citations that tools served and flags ones they didn't" do
    check = CitationValidator.call(
      content: "Chapters are inductance [§2801] and capacitance [§3901], appendices [§9999].",
      served_positions: [ 2801, 3901 ]
    )

    assert_equal [ 2801, 3901, 9999 ], check.cited
    assert_equal [ 9999 ], check.unverified
    assert_not check.valid?
  end

  test "passes clean answers and handles no citations" do
    assert CitationValidator.call(content: "See [§12].", served_positions: [ 12 ]).valid?
    assert CitationValidator.call(content: "No citations here.", served_positions: []).valid?
  end

  test "range citations only verify the explicitly tagged position" do
    check = CitationValidator.call(content: "[§3901-3902]", served_positions: [ 3901 ])
    assert_equal [ 3901 ], check.cited
    assert check.valid?
  end
end
