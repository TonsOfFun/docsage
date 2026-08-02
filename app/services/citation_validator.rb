# Deterministically verifies the §N citations in an answer against what the
# tools actually served during the run. The model claims grounding; this
# checks it: a citation is verified only if that exact chunk position came
# back in a tool result this conversation. Nonexistent positions are by
# definition unserved, so both fabrication modes are caught.
class CitationValidator
  Result = Struct.new(:cited, :unverified, keyword_init: true) do
    def valid? = unverified.empty?

    def to_h
      { "cited" => cited, "unverified" => unverified }
    end
  end

  def self.call(content:, served_positions:)
    cited = content.to_s.scan(/§(\d+)/).flatten.map(&:to_i).uniq
    served = Array(served_positions).map(&:to_i)
    Result.new(cited: cited, unverified: cited - served)
  end
end
