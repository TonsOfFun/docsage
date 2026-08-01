module DocumentsHelper
  # Renders an assistant answer: strips model reasoning blocks, escapes,
  # then turns every §N citation into a link to that passage's anchor on the
  # page. [§12], (§12), and bare §12 all resolve.
  def render_answer(content, chunks_by_position)
    visible = content.to_s.gsub(%r{<think>.*?</think>}m, "").strip
    escaped = ERB::Util.html_escape(visible)

    linked = escaped.gsub(/§(\d+)/) do
      position = Regexp.last_match(1).to_i
      if chunks_by_position.key?(position)
        %(<a class="citation" href="#chunk-#{position}">§#{position}</a>)
      else
        "§#{position}"
      end
    end

    simple_format(linked, {}, sanitize: false) # rubocop:disable Rails/OutputSafety
  end

  def status_badge(document)
    tone = { "ready" => "ok", "processing" => "busy", "failed" => "err" }.fetch(document.status, "busy")
    content_tag(:span, document.status, class: "badge badge-#{tone}")
  end
end
