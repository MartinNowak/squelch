module squelch.format;

import std.algorithm.comparison;
import std.algorithm.searching;
import std.array;
import std.exception;
import std.range;
import std.stdio : File;
import std.sumtype : match;

import squelch.common;

Token[] format(Token[] tokens)
{
	Token[] result;

	enum WhiteSpace
	{
		none,
		space,
		newLine,
		blankLine,
	}

	WhiteSpace wsLast;
	bool wasWord;
	string[] stack;

	foreach (ref token; tokens)
	{
		WhiteSpace wsPre, wsPost;
		void delegate()[] post;
		bool isWord;

		token.match!(
			(ref TokenWhiteSpace t)
			{
				assert(false);
			},
			(ref TokenComment t)
			{
				wsPre = wsPost = WhiteSpace.newLine;
			},
			(ref TokenKeyword t)
			{
				isWord = true;
				wsPre = wsPost = WhiteSpace.space;
				switch (t.text)
				{
					case "SELECT":
					case "SELECT AS STRUCT":
						wsPre = wsPost = WhiteSpace.newLine;
						if (stack.endsWith("WITH"))
							stack.popBack();
						post ~= { stack ~= "SELECT"; };
						break;
					case "FROM":
					case "WHERE":
					case "JOIN":
					case "CROSS JOIN":
					case "INNER JOIN":
					case "LEFT JOIN":
					case "LEFT OUTER JOIN":
					case "RIGHT JOIN":
					case "RIGHT OUTER JOIN":
					case "ORDER BY":
					case "PARTITION BY":
						wsPre = wsPost = WhiteSpace.newLine;
						if (stack.endsWith("SELECT"))
							stack.popBack();
						post ~= { stack ~= "SELECT"; };
						break;
					case "WINDOW":
						wsPre = WhiteSpace.newLine;
						if (stack.endsWith("SELECT"))
							stack.popBack();
						post ~= { stack ~= "SELECT"; };
						break;
					case "WITH":
						wsPre = wsPost = WhiteSpace.newLine;
						post ~= { stack ~= "WITH"; };
						break;
					case "USING":
						wsPre = WhiteSpace.newLine;
						break;
					default:
						break;
				}
			},
			(ref TokenIdentifier t)
			{
				isWord = true; // Technically not, but we treat it as one for formatting purposes.
			},
			(ref TokenNamedParameter t)
			{
				isWord = true;
			},
			(ref TokenOperator t)
			{
				switch (t.text)
				{
					case ".":
					case "<":
					case ">":
						break;
					case "(":
						wsPost = WhiteSpace.newLine;
						post ~= { stack ~= "("; };
						break;
					case ")":
						wsPre = WhiteSpace.newLine;
						stack = retro(find(retro(stack), "("));
						enforce(stack.length, "Mismatched )");
						stack = stack[0 .. $-1];
						break;
					case "[":
						wsPost = WhiteSpace.newLine;
						post ~= { stack ~= "["; };
						break;
					case "]":
						wsPre = WhiteSpace.newLine;
						stack = retro(find(retro(stack), "["));
						enforce(stack.length, "Mismatched ]");
						stack = stack[0 .. $-1];
						break;
					case ",":
						wsPost = WhiteSpace.newLine;
						break;
					case ";":
						wsPost = WhiteSpace.blankLine;
						while (stack.endsWith("SELECT") || stack.endsWith("WITH"))
							stack.popBack();
						break;
					default:
						// Binary operators and others
						wsPre = wsPost = WhiteSpace.space;
						break;
				}
			},
			(ref TokenString t)
			{
				isWord = true;
			},
			(ref TokenNumber t)
			{
				isWord = true;
			},
			(ref TokenDbtStatement t)
			{
				wsPre = wsPost = WhiteSpace.newLine;
				switch (t.kind)
				{
					case "for":
					case "if":
					case "macro":
					case "filter":
						post ~= { stack ~= "%" ~ t.kind; };
						break;
					case "set":
						if (!t.text.canFind('='))
							post ~= { stack ~= "%" ~ t.kind; };
						break;
					case "elif":
					case "else":
						while (stack.length && !stack[$-1].startsWith("%")) stack.popBack();
						enforce(stack.endsWith("%if"),
							"Found " ~ t.kind ~ " but expected " ~ (stack.length ? "end" ~ stack[$-1][1..$] : "end-of-file")
						);
						stack.popBack();
						post ~= { stack ~= "%if"; };
						break;
					case "endfor":
					case "endif":
					case "endmacro":
					case "endfilter":
					case "endset":
						while (stack.length && !stack[$-1].startsWith("%")) stack.popBack();
						enforce(stack.endsWith("%" ~ t.kind[3 .. $]),
							"Found " ~ t.kind ~ " but expected " ~ (stack.length ? "end" ~ stack[$-1][1..$] : "end-of-file")
						);
						stack.popBack();
						break;
					default:
						break;
				}
			},
			(ref TokenDbtComment t)
			{
			},
		);

		wsPre = max(wsLast, wsPre);
		if (!wsPre && wasWord && isWord)
			wsPre = WhiteSpace.space;
		if (!result.length)
			wsPre = WhiteSpace.none;

		final switch (wsPre)
		{
			case WhiteSpace.none:
				break;
			case WhiteSpace.space:
				result ~= Token(TokenWhiteSpace(" "));
				break;
			case WhiteSpace.blankLine:
				result ~= Token(TokenWhiteSpace("\n"));
				goto case;
			case WhiteSpace.newLine:
				auto indent = stack.length;
				result ~= Token(TokenWhiteSpace("\n" ~ "\t".replicate(indent)));
				break;
		}

		result ~= token;
		foreach (fun; post)
			fun();

		wsLast = wsPost;
		wasWord = isWord;
	}

	if (tokens.length)
		result ~= Token(TokenWhiteSpace("\n"));

	return result;
}
