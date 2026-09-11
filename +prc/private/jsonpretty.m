function out = jsonpretty(txt, indentWidth)
% JSONPRETTY - Re-indent compact jsonencode output.
%
% jsonencode only learned 'PrettyPrint' in R2021a and prcNIR supports R2020b,
% so the formatting is done here. Settings files are meant to be hand-edited;
% a single 4kB line would make that a lie.

if nargin < 2, indentWidth = 2; end

txt   = char(txt);
out   = blanks(0);
depth = 0;
inStr = false;
esc   = false;
pad   = @(n) repmat(' ', 1, n * indentWidth);

for i = 1:numel(txt)
    ch = txt(i);

    %-- inside a string literal nothing is structural
    if inStr
        out(end+1) = ch; %#ok<AGROW>
        if esc,             esc = false;
        elseif ch == '\',   esc = true;
        elseif ch == '"',   inStr = false;
        end
        continue
    end

    switch ch
        case '"'
            inStr = true;
            out(end+1) = ch; %#ok<AGROW>
        case {'{','['}
            depth = depth + 1;
            out = [out ch newline pad(depth)]; %#ok<AGROW>
        case {'}',']'}
            depth = max(depth - 1, 0);
            out = [out newline pad(depth) ch]; %#ok<AGROW>
        case ','
            out = [out ch newline pad(depth)]; %#ok<AGROW>
        case ':'
            out = [out ': ']; %#ok<AGROW>
        otherwise
            out(end+1) = ch; %#ok<AGROW>
    end
end

%-- collapse the empty containers this leaves behind: "[\n  ]" -> "[]"
out = regexprep(out, '\[\s*\]', '[]');
out = regexprep(out, '\{\s*\}', '{}');
end
