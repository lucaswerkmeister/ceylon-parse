import ceylon.parse { Grammar, Token, rule, tokenizer, lassoc }
import ceylon.language.meta.model { Class }
import ceylon.ast.core {
    AnyCompilationUnit,
    Node,
    LIdentifier,
    UIdentifier,
    Key,
    ScopedKey,
    IntegerLiteral,
    CharacterLiteral,
    StringLiteral,
    UnionType,
    IterableType,
    UnionableType,
    MainType,
    Type,
    TypeName,
    TypeArguments,
    TypeNameWithTypeArguments,
    TupleType,
    SimpleType,
    BaseType,
    GroupedType,
    OptionalType,
    SequentialType,
    QualifiedType,
    VariadicType,
    CallableType,
    TypeList,
    DefaultedType,
    IntersectionType,
    PrimaryType,
    MemberName,
    CaseTypes,
    EntryType,
    PositionalArguments,
    ExtendedType,
    ASTSuper = Super,
    ClassInstantiation,
    SatisfiedTypes,
    TypeParameters,
    TypeParameter,
    Variance,
    InModifier,
    OutModifier,
    TypeConstraint,
    TypeArgument,
    FloatLiteral
}

"AST Node key to attach individual tokens"
shared Key<CeylonToken[]> tokensKey = ScopedKey<CeylonToken[]>(`package
        ceylon.parse.ceylon`, "tokens");

"List of reserved words"
String[] reservedWords = ["assembly", "module", "package", "import", "alias",
    "class", "interface", "object", "given", "value", "assign", "void",
    "function", "new", "of", "extends", "satisfies", "abstracts", "in", "out",
    "return", "break", "continue", "throw", "assert", "dynamic", "if", "else",
    "switch", "case", "for", "while", "try", "catch", "finally", "then", "let",
    "this", "outer", "super", "is", "exists", "nonempty"];

"List of whitespace characters"
Character[] whitespaceChars = [ ' ', '\{FORM FEED (FF)}',
       '\{LINE FEED (LF)}', '\{CHARACTER TABULATION}',
       '\{CARRIAGE RETURN (CR)}'];

"Extract the ending line and column from an object which is assumed to be a
 CeylonToken, for use as a starting position for the next token"
[Integer, Integer] extractStartPos(Object? tok) {
    if (is CeylonToken tok) {
        return [tok.line_end, tok.col_end];
    }

    return [0, 0];
}

"Literal token"
Token<Type>? literal<Type>(Class<Type, [Integer,Integer,Integer,Integer]> t,
        String input, Object? prev, String+ wants)
        given Type satisfies Object {
    value [start_line, start_col] = extractStartPos(prev);

    for (want in wants) {
        if (input.startsWith(want)) {
            return Token(t(start_line, start_col, start_line,
                        start_col + want.size), want.size);
        }
    }

    return null;
}

"Parse a single-character token"
Token<Type>? takeCharToken<Type>(Class<Type, [Integer, Integer, Integer,
        Integer]>|Class<Type, [String, Integer, Integer, Integer,
        Integer]> t, String input, Object? prev, Boolean(Character) test)
        given Type satisfies Object {
    value [start_line, start_col] = extractStartPos(prev);
    value char = input[0];

    if (! exists char) { return null; }
    assert(exists char);

    if (! test(char)) { return null; }

    if (is Class<Type, [Integer, Integer, Integer, Integer]> t) {
        return Token(t(start_line, start_col, start_line, start_col + 1), 1);
    } else {
        return Token(t(input[0:1], start_line, start_col, start_line, start_col
                    + 1), 1);
    }
}

"Parse a token that consists of all characters at the head of the string for
 which the test function returns true."
Token<Type>? takeTokenWhile<Type>(Class<Type, [Integer, Integer, Integer,
        Integer]>|Class<Type, [String, Integer, Integer, Integer,
        Integer]> t, String input, Object? prev, Boolean(String)|Boolean(Character) test)
        given Type satisfies Object {
    value [start_line, start_col] = extractStartPos(prev);

    variable value length = 0;

    if (is Boolean(String) test) {
        while (test(input[length...])) { length++; }
    } else {
        while (exists c = input[length], test(c)) { length++; }
    }

    value [end_line, end_col] = calculateStopPos(start_line, start_col,
            input[0:length]);

    if (length == 0) { return null; }

    if (is Class<Type, [Integer, Integer, Integer, Integer]> t) {
        return Token(t(start_line, start_col, end_line, end_col), length);
    } else {
        return Token(t(input[0:length], start_line, start_col, end_line,
                    end_col), length);
    }
}

"Meta token"
Type meta<Type>(Class<Type, [CeylonToken+]> t,
        CeylonToken|{CeylonToken|Node*}|Node?* children) {

    assert( is [CeylonToken+] toks = tokenStream(*children));

    return t(*toks);
}

"AST Node"
NodeType astNode<NodeType, Arguments>(Class<NodeType, Arguments> t,
        Arguments args, CeylonToken|{CeylonToken|Node*}|Node?* children)
        given NodeType satisfies Node
        given Arguments satisfies [Anything*] {
    value ret = t(*args);
    ret.put(tokensKey, tokenStream(*children));
    return ret;
}

"AST Text Node"
NodeType astTextNode<NodeType>(Class<NodeType, [String]> t,
        CeylonToken|{CeylonToken|Node*}|Node?* children)
        given NodeType satisfies Node {
    assert(is [CeylonToken+]tstream = tokenStream(*children));
    value ret = t(tokenText(*tstream));
    ret.put(tokensKey, tstream);
    return ret;
}

"Text from a stream of tokens"
String tokenText(CeylonToken+ token) {
    return (token*.text).fold("")((x,y)=>x+y);
}

"Extract all tokens from a series of arguments to a production"
CeylonToken[] tokenStream(CeylonToken|{CeylonToken|Node*}|Node?* args) {
    variable CeylonToken[] ret = [];

    for (arg in args) {
        if (! exists arg) {
            continue;
        } else if (is CeylonMetaToken arg) {
            ret = ret.append(tokenStream(*arg.subtokens));
        } else if (is CeylonToken arg) {
            ret = ret.withTrailing(arg);
        } else if (is {CeylonToken|Node*} arg) {
            ret = ret.append(tokenStream(*arg));
        } else {
            assert(exists k = arg.get(tokensKey));
            ret.append(k);
        }
    }

    return ret;
}

"Calculate the ending line and column given the starting line and column and
 the intervening text"
[Integer, Integer] calculateStopPos(Integer start_line, Integer start_col,
        String text) {
    variable value line = start_line;
    variable value col = start_col;
    variable value i = 0;

    while (exists c = text[i]) {
        if (text[i...].startsWith("\r\n")) {
            i++; // We'll detect the linebreak later, just note that it's long
        }

        if (c == '\r' || c == '\n') {
            line++;
            col = 0;
        } else {
            col++;
        }

        i++; // Possibly the second increment if we're skipping \r\n
    }

    return [line, col];
}

"A parse tree for the Ceylon language"
by("Casey Dahlin")
object ceylonGrammar extends Grammar<AnyCompilationUnit, String>() {

    "Section 2.2 of the specification"
    tokenizer
    shared Token<Whitespace>? whitespace(String input, Object? prev)
            => takeTokenWhile(`Whitespace`, input, prev,
                    whitespaceChars.contains);

    "Section 2.2 of the specification"
    tokenizer
    shared Token<LineComment>? lineComment(String input, Object? prev) {
        value [start_line, start_col] = extractStartPos(prev);
        if (! (input.startsWith("//") || input.startsWith("#!"))) {
            return null;
        }

        variable value i = 2;

        while (exists c = input[i], c != '\r', c != '\n') { i++; }

        return Token(LineComment(start_line, start_col, start_line, start_col +
                    i), i);
    }

    "Section 2.2 of the specification"
    tokenizer
    shared Token<CommentStart>? commentStart(String input, Object? prev)
            => literal(`CommentStart`, input, prev, "/*");

    "Section 2.2 of the specification"
    tokenizer
    shared Token<CommentEnd>? commentEnd(String input, Object? prev)
            => literal(`CommentEnd`, input, prev, "*/");

    "Section 2.2 of the specification"
    tokenizer
    shared Token<CommentBody>? commentBody(String input, Object? prev)
            => takeTokenWhile(`CommentBody`, input, prev,
                    (String x) => ! (x.startsWith("/*") || x.startsWith(
                            "*/")));

    "Section 2.2 of the specification"
    rule
    shared BlockComment blockComment(CommentStart start,
            {CommentBody|BlockComment*} body, CommentEnd end)
            => meta(`BlockComment`, start, body, end);

    "Section 2.2 of the specification"
    rule
    shared AnySym separator<AnySym>(
            {BlockComment|LineComment|Whitespace*} before,
            AnySym sym,
            {BlockComment|LineComment|Whitespace*} after)
            => sym;

    "Section 2.3 of the specification"
    tokenizer
    shared Token<UIdentStart>? uIdentStart(String input, Object? prev)
            => literal(`UIdentStart`, input, prev, "\\I");

    "Section 2.3 of the specification"
    tokenizer
    shared Token<LIdentStart>? lIdentStart(String input, Object? prev)
            => literal(`LIdentStart`, input, prev, "\\i");

    "Section 2.3 of the specification"
    tokenizer
    shared Token<UIdentText>? uIdentText(String input, Object? prev) {
        value [start_line, start_col] = extractStartPos(prev);
        variable value i = 0;

        while (exists c = input[i], c.letter || (i > 0 && c.digit) || c == '_') { i++; }

        if (i == 0) { return null; }

        assert(exists c = input[0]);
        if (! c.uppercase) { return null; }

        return Token(UIdentText(input[0:i], start_line, start_col, start_line,
                    start_col + i), i);
    }

    "Section 2.3 of the specification"
    tokenizer
    shared Token<LIdentText>? lIdentText(String input, Object? prev) {
        value [start_line, start_col] = extractStartPos(prev);
        variable value i = 0;

        while (exists c = input[i], c.letter || (i > 0 && c.digit) || c == '_') { i++; }

        if (i == 0) { return null; }

        assert(exists c = input[0]);
        if (! c.lowercase) { return null; }
        if (reservedWords.contains(input[0:i])) { return null; }

        return Token(LIdentText(input[0:i], start_line, start_col, start_line,
                    start_col + i), i);
    }

    "Section 2.3 of the specification"
    rule
    shared UIdentifier uident(UIdentStart? start, UIdentText text)
            => astNode(`UIdentifier`, [text.text], start, text);

    "Section 2.3 of the specification"
    rule
    shared UIdentifier uidentEsc(UIdentStart start, LIdentText text)
            => astNode(`UIdentifier`, [text.text, true], start, text);

    "Section 2.3 of the specification"
    rule
    shared LIdentifier lident(LIdentStart? start, LIdentText text)
            => astNode(`LIdentifier`, [text.text], start, text);

    "Section 2.3 of the specification"
    rule
    shared LIdentifier lidentEsc(LIdentStart start,
            UIdentText text)
            => astNode(`LIdentifier`, [text.text, true], start, text);

    "Section 2.4.1 of the specification"
    tokenizer
    shared Token<HashMark>? hashMark(String input, Object? prev)
            => literal(`HashMark`, input, prev, "#");

    "Section 2.4.1 of the specification"
    tokenizer
    shared Token<DollarMark>? dollarMark(String input, Object? prev)
            => literal(`DollarMark`, input, prev, "$");

    "Section 2.4.1 of the specification"
    tokenizer
    shared Token<Underscore>? underscore(String input, Object? prev)
            => literal(`Underscore`, input, prev, "_");

    "Section 2.4.1 of the specification"
    tokenizer
    shared Token<Digit>? digit(String input, Object? prev)
            => takeCharToken(`Digit`, input, prev, (Character x) => x.digit);

    "Section 2.4.1 of the specification"
    tokenizer
    shared Token<HexDigit>? hexDigit(String input, Object? prev)
            => takeCharToken(`HexDigit`, input, prev, (x) => x.digit ||
                    "abcdefABCDEF".contains(x));

    "Section 2.4.1 of the specification"
    tokenizer
    shared Token<BinDigit>? binDigit(String input, Object? prev)
            => takeCharToken(`BinDigit`, input, prev, "01".contains);

    "Section 2.4.1 of the specification"
    rule
    shared Digits digits({Digit+} items) => Digits(*items);

    "Section 2.4.1 of the specification"
    rule
    shared DigitCluster digitCluster(Underscore u, Digit a, Digit b,
            Digit c) => DigitCluster(u,a,b,c);

    "Section 2.4.1 of the specification"
    rule
    shared Digits clusteredDigits(Digit? a, Digit? b, Digit c,
            {DigitCluster+} clusters)
            => meta(`Digits`, a, b, c, clusters);

    "Section 2.4.1 of the specification"
    rule
    shared FracDigitCluster fracDigitCluster(Digit a, Digit b, Digit c,
            Underscore u) => FracDigitCluster(a,b,c,u);

    "Section 2.4.1 of the specification"
    rule
    shared FracDigits fracDigits({FracDigitCluster+} clusters,
            Digit a, Digit? b, Digit? c)
            => meta(`FracDigits`, clusters, a, b, c);

    "Section 2.4.1 of the specification"
    rule
    shared FracDigits unmarkedFracDigits({Digits+} digits) => FracDigits(*digits);


    "Section 2.4.1 of the specification"
    rule
    shared HexDigitCluster hexFourCluster(Underscore u, HexDigit a, HexDigit b,
            HexDigit c, HexDigit d) => HexDigitCluster(u,a,b,c,d);

    "Section 2.4.1 of the specification"
    rule
    shared HexDigitTwoCluster hexTwoCluster(Underscore u, HexDigit a,
            HexDigit b) => HexDigitTwoCluster(u,a,b);

    "Section 2.4.1 of the specification"
    rule
    shared BinDigitCluster binCluster(Underscore u, BinDigit a, BinDigit b,
            BinDigit c, BinDigit d) => BinDigitCluster(u,a,b,c,d);

    "Section 2.4.1 of the specification"
    rule
    shared BinDigits binDigits({BinDigit+} digits) => BinDigits(*digits);

    "Section 2.4.1 of the specification"
    rule
    shared BinDigits clusteredBinDigits(BinDigit? a, BinDigit? b, BinDigit? c,
            BinDigit d, {BinDigitCluster+} clusters)
            => meta(`BinDigits`, a, b, c, d, clusters);

    "Section 2.4.1 of the specification"
    rule
    shared HexDigits hexDigits({HexDigit+} digits) => HexDigits(*digits);

    "Section 2.4.1 of the specification"
    rule
    shared HexDigits clusteredHexDigits(HexDigit? a, HexDigit? b, HexDigit? c,
            HexDigit d, {HexDigitCluster+} clusters)
            => meta(`HexDigits`, a, b, c, d, clusters);

    "Section 2.4.1 of the specification"
    rule
    shared HexDigits twoClusteredHexDigits(HexDigit? a, HexDigit b,
            {HexDigitTwoCluster+} clusters)
            => meta(`HexDigits`, a, b, clusters);

    "Section 2.4.1 of the specification"
    rule
    shared IntegerLiteral hexLiteral(HashMark h, {HexDigits+} digits)
            => astTextNode(`IntegerLiteral`, h, digits);

    "Section 2.4.1 of the specification"
    rule
    shared IntegerLiteral binLiteral(DollarMark h, {BinDigits+} digits)
            => astTextNode(`IntegerLiteral`, h, digits);

    "Section 2.4.1 of the specification"
    tokenizer
    shared Token<Magnitude>? magnitude(String input, Object? prev)
            => takeCharToken(`Magnitude`, input, prev, "kMGTP".contains);

    "Section 2.4.1 of the specification"
    tokenizer
    shared Token<Minitude>? minitude(String input, Object? prev)
            => takeCharToken(`Minitude`, input, prev, "munpf".contains);

    "Section 2.4.1 of the specification"
    rule
    shared IntegerLiteral decLiteral({Digits+} digits,
            Magnitude? m)
            => astTextNode(`IntegerLiteral`, digits, m);

    "Section 2.4.1 of the specification"
    tokenizer
    shared Token<ExpMarker>? expMarker(String input, Object? prev)
            => takeCharToken(`ExpMarker`, input, prev, "eE".contains);

    "Section 2.4.1 of the specification"
    tokenizer
    shared Token<Plus>? plus(String input, Object? prev)
            => literal(`Plus`, input, prev, "+");

    "Section 2.4.1 of the specification"
    tokenizer
    shared Token<Minus>? minus(String input, Object? prev)
            => literal(`Minus`, input, prev, "-");

    "Section 2.4.1 of the specification"
    tokenizer
    shared Token<Dot>? dot(String input, Object? prev)
            => literal(`Dot`, input, prev, ".");

    "Section 2.4.1 of the specification"
    rule
    shared Exponent exponent(ExpMarker e, Plus|Minus? s, {Digit+} digits)
            => meta(`Exponent`, e, s, digits);

    "Section 2.4.1 of the specification"
    rule
    shared FloatLiteral floatLiteral({Digits+} digits, Dot dot,
            {FracDigits+} fracs, Magnitude|Minitude|Exponent? m)
            => astTextNode(`FloatLiteral`, digits, dot, fracs, m);

    "Section 2.4.1 of the specification"
    rule
    shared FloatLiteral shortcutFloatLiteral({Digits+} digits, Minitude m)
            => astTextNode(`FloatLiteral`, digits, m);

    "Section 2.4.2 of the specification"
    tokenizer
    shared Token<Quote>? quote(String input, Object? prev)
            => literal(`Quote`, input, prev, "'");

    "Section 2.4.2 of the specification"
    tokenizer
    shared Token<CharacterLiteralTok>? characterLiteralTok(String input, Object? prev) {
        value [start_line, start_col] = extractStartPos(prev);

        if (! input[0] exists) { return null; }

        variable value i = 0;
        variable value skip = false;

        while (exists c = input[0], c != "'" || skip) {
            skip = c == '\\' && !skip;
            i++;
        }

        if (! input[i] exists) { return null; }
        if (exists c = input[i], c != "'") { return null; }

        value [end_line, end_col] = calculateStopPos(start_line, start_col,
                input[0:i]);
        return Token(CharacterLiteralTok(input[0:i], start_line, start_col,
                    end_line, end_col), i);
    }

    "Section 2.4.2 of the specification"
    rule
    shared CharacterLiteral characterLiteral(Quote a,
            CharacterLiteralTok t, Quote b)
            => astNode(`CharacterLiteral`, [t.text], a, t, b);

    "Section 2.4.3 of the specification"
    tokenizer
    shared Token<DoubleQuote>? doubleQuote(String input, Object? prev)
            => literal(`DoubleQuote`, input, prev, "\"");

    "Section 2.4.3 of the specification"
    tokenizer
    shared Token<StringLiteralTok>? stringLiteralTok(String input, Object? prev) {
        value [start_line, start_col] = extractStartPos(prev);

        if (! input[0] exists) { return null; }

        variable value i = 0;
        variable value skip = false;

        while (exists c = input[0], c != "\"" || skip) {
            skip = c == '\\' && !skip;
            i++;
        }

        if (! input[i] exists) { return null; }
        if (exists c = input[i], c != "\"") { return null; }

        value [end_line, end_col] = calculateStopPos(start_line, start_col,
                input[0:i]);
        return Token(StringLiteralTok(input[0:i], start_line, start_col,
                    end_line, end_col), i);
    }

    "Section 2.4.2 of the specification"
    rule
    shared StringLiteral stringLiteral(DoubleQuote a,
            StringLiteralTok t, DoubleQuote b)
            => astNode(`StringLiteral`, [t.text], a, t, b);

    "Section 3.2.3 of the specification"
    tokenizer
    shared Token<Pipe>? pipe(String input, Object? prev)
            => literal(`Pipe`, input, prev, "|");

    "Section 3.2.3 of the specification"
    rule(0, lassoc)
    shared UnionType unionType(MainType a, Pipe p, MainType b) {
        [IntersectionType|PrimaryType+] left_children;
        [IntersectionType|PrimaryType+] right_children;

        if (is UnionType a) {
            left_children = a.children;
        } else {
            left_children = [a];
        }

        if (is UnionType b) {
            right_children = b.children;
        } else {
            right_children = [b];
        }

        return astNode(`UnionType`, [left_children.append(right_children)], a, p, b);
    }

    "Section 3.2.4 of the specification"
    tokenizer
    shared Token<Ampersand>? ampersand(String input, Object? prev)
            => literal(`Ampersand`, input, prev, "&");

    "Section 3.2.4 of the specification"
    rule(1, lassoc)
    shared IntersectionType intersectionType(UnionableType a, Ampersand p,
            UnionableType b) {
        [PrimaryType+] left_children;
        [PrimaryType+] right_children;

        if (is IntersectionType a) {
            left_children = a.children;
        } else {
            left_children = [a];
        }

        if (is IntersectionType b) {
            right_children = b.children;
        } else {
            right_children = [b];
        }

        return astNode(`IntersectionType`, [left_children.append(right_children)], a, p, b);
    }

    "Section 3.2.7 of the specification"
    tokenizer
    shared Token<LT>? lessThan(String input, Object? prev)
            => literal(`LT`, input, prev, "<");

    "Section 3.2.7 of the specification"
    tokenizer
    shared Token<GT>? greaterThan(String input, Object? prev)
            => literal(`GT`, input, prev, "<");

    "Section 3.2.7 of the specification"
    rule
    shared GroupedType groupedType(LT a, Type t, GT b)
            => astNode(`GroupedType`, [t], a, t, b);

    "Section 3.2.7 of the specification"
    rule
    shared TypeNameWithTypeArguments typeNameWithArguments(TypeName name,
            TypeArguments? args)
            => astNode(`TypeNameWithTypeArguments`, [name, args], name, args);

    "Section 3.2.7 of the specification"
    rule
    shared BaseType baseType(TypeNameWithTypeArguments type)
            => astNode(`BaseType`, [type], type);

    "Section 3.2.7 of the specification"
    rule
    shared QualifiedType qualifiedType(SimpleType|GroupedType base,
            TypeNameWithTypeArguments type)
            => astNode(`QualifiedType`, [base, type], base, type);

    "Section 3.2.8 of the specification"
    tokenizer
    shared Token<Question>? question(String input, Object? prev)
            => literal(`Question`, input, prev, "?");

    "Section 3.2.8 of the specification"
    rule
    shared OptionalType optionalType(PrimaryType type, Question q)
            => astNode(`OptionalType`, [type], type, q);

    "Section 3.2.8 of the specification"
    tokenizer
    shared Token<SqOpen>? sqOpen(String input, Object? prev)
            => literal(`SqOpen`, input, prev, "[");

    "Section 3.2.8 of the specification"
    tokenizer
    shared Token<SqClose>? sqClose(String input, Object? prev)
            => literal(`SqClose`, input, prev, "]");

    "Section 3.2.8 of the specification"
    tokenizer
    shared Token<ParOpen>? parOpen(String input, Object? prev)
            => literal(`ParOpen`, input, prev, "(");

    "Section 3.2.8 of the specification"
    tokenizer
    shared Token<ParClose>? parClose(String input, Object? prev)
            => literal(`ParClose`, input, prev, ")");

    "Section 3.2.8 of the specification"
    tokenizer
    shared Token<Comma>? comma(String input, Object? prev)
            => literal(`Comma`, input, prev, ",");

    "Section 3.2.8 of the specification"
    rule
    shared SequentialType sequentialType(PrimaryType type,
            SqOpen a, SqClose b) => astNode(`SequentialType`, [type], a, b);

    "Section 3.2.8 of the specification"
    rule
    shared CommaSepList<ItemType> commaSepList<ItemType>(ItemType t)
            given ItemType satisfies Node {
            assert(is [CeylonToken+] ts = tokenStream(t));
            return CommaSepList<ItemType>([t], *ts);
    }

    "Section 3.2.8 of the specification"
    rule
    shared CommaSepList<ItemType>
    commaSepListMulti<ItemType>(CommaSepList<ItemType> prior, Comma c, ItemType t)
            given ItemType satisfies Node
            => CommaSepList<ItemType>([*prior.nodes.chain({t})],
                    *prior.tokens.chain({c}).chain(tokenStream(t)));

    "Section 3.2.8 of the specification"
    rule
    shared TypeList typeList(CommaSepList<Type|DefaultedType> items)
            => astNode(`TypeList`, [items.nodes, null], *items.nodes);

    "Section 3.2.8 of the specification"
    rule
    shared TypeList typeListVar(CommaSepList<Type|DefaultedType> items,
            Comma c, VariadicType v)
            => astNode(`TypeList`, [items.nodes, v], *items.nodes.chain({c, v}));

    "Section 3.2.8 of the specification"
    rule
    shared TypeList emptyTypeList()
            => astNode(`TypeList`, [[], null]);

    "Section 3.2.8 of the specification"
    rule
    shared CallableType callableType(PrimaryType ret, ParOpen a,
            TypeList types, ParClose b)
            => astNode(`CallableType`, [ret, types], ret, a, types, b);

    "Section 3.2.8 of the specification"
    tokenizer
    shared Token<CurlOpen>? curlOpen(String input, Object? prev)
            => literal(`CurlOpen`, input, prev, "{");

    "Section 3.2.8 of the specification"
    tokenizer
    shared Token<CurlClose>? curlClose(String input, Object? prev)
            => literal(`CurlClose`, input, prev, "}");

    "Section 3.2.8 of the specification"
    tokenizer
    shared Token<Star>? star(String input, Object? prev)
            => literal(`Star`, input, prev, "*");

    "Section 3.2.8 of the specification"
    rule
    shared IterableType iterableType(CurlOpen a, VariadicType? type,
            CurlClose b)
            => astNode(`IterableType`, [type], a, type, b);

    "Section 3.2.8 of the specification"
    rule
    shared TupleType tupleType(SqOpen a, TypeList types, SqClose b)
            => astNode(`TupleType`, [types], a, types, b);

    "Section 3.2.8 of the specification"
    rule
    shared VariadicType variadicType(MainType type, Plus|Star quality)
            => astNode(`VariadicType`, [type, quality is Plus], type, quality);

    "Section 3.2.8 of the specification"
    tokenizer
    shared Token<Eq>? eq(String input, Object? prev)
            => literal(`Eq`, input, prev, "=");

    "Section 3.2.8 of the specification"
    rule
    shared DefaultedType defaultedType(Type type, Eq e)
            => astNode(`DefaultedType`, [type], type, e);

    "Section 3.2.8 of the specification"
    tokenizer
    shared Token<Arrow>? arrow(String input, Object? prev)
            => literal(`Arrow`, input, prev, "->");

    "Section 3.2.8 of the specification"
    rule
    shared EntryType entryType(MainType key, Arrow a, MainType item)
            => astNode(`EntryType`, [key, item], key, a, item);

    "Section 3.3.2 of the specification"
    tokenizer
    shared Token<Extends>? extends_(String input, Object? prev)
            => literal(`Extends`, input, prev, "extends");

    "Section 3.3.2 of the specification"
    tokenizer
    shared Token<Super>? super_(String input, Object? prev)
            => literal(`Super`, input, prev, "super");

    "Section 3.3.2 of the specification"
    rule
    shared SuperDot superDot(Super s, Dot d)
            => meta(`SuperDot`, s, d);

    "Section 3.3.2 of the specification"
    rule 
    shared ClassInstantiation classInstantiation(SuperDot? sup,
            TypeNameWithTypeArguments type, PositionalArguments args)
            => astNode(`ClassInstantiation`, [type, args, if (exists sup) then
            ASTSuper() else null], sup, type, args);

    "Section 3.3.2 of the specification"
    rule
    shared ExtendedType extendedType(Extends e, ClassInstantiation inst)
            => astNode(`ExtendedType`, [inst], e, inst);

    "Section 3.3.3 of the specification"
    tokenizer
    shared Token<Satisfies>? satisfies_(String input, Object? prev)
            => literal(`Satisfies`, input, prev, "satisfies");

    "Section 3.3.3 of the specification"
    rule
    shared AmpersandPrimary ampersandPrimary(Ampersand and, PrimaryType p)
            => AmpersandPrimary(p, and, *tokenStream(p));

    "Section 3.3.3 of the specification"
    rule
    shared SatisfiedTypes satisfiedTypes(PrimaryType p,
            [AmpersandPrimary*] more)
            => astNode(`SatisfiedTypes`, [[p, *more*.type]], p, *more*.tokens);

    "Section 3.4.2 of the specification"
    rule
    shared PipePrimaryOrMember pipePrimaryOrMember(Ampersand and,
            PrimaryType|MemberName p)
            => PipePrimaryOrMember(p, and, *tokenStream(p));

    "Section 3.4.2 of the specification"
    tokenizer
    shared Token<Of>? of_(String input, Object? prev)
            => literal(`Of`, input, prev, "of");

    "Section 3.4.2 of the specification"
    rule
    shared CaseTypes caseTypes(Of o, PrimaryType|MemberName p,
            [PipePrimaryOrMember *] more)
            => astNode(`CaseTypes`, [[p, *more*.type]], p, *more*.tokens);

    "Section 3.5 of the specification"
    rule
    shared TypeParameters typeParameters(LT a, CommaSepList<TypeParameter>
            list, GT b)
            => astNode(`TypeParameters`, [list.nodes], a, list.tokens, b);

    "Section 3.5.1 of the specification"
    rule
    shared EqualsType equalsType(Eq eq, Type type)
            => EqualsType(type, eq, *tokenStream(type));

    "Section 3.5.1 of the specification"
    rule
    shared TypeParameter typeParameter(Variance? var, TypeName name,
            EqualsType? eq)
            => astNode(`TypeParameter`, [name, var, if (exists eq) then
                    eq.type else null], var, name, if (exists eq) then
                    eq.tokens else null);

    "Section 3.5.1 of the specification"
    tokenizer
    shared Token<In>? in_(String input, Object? prev)
            => literal(`In`, input, prev, "in");

    "Section 3.5.1 of the specification"
    tokenizer
    shared Token<Out>? out_(String input, Object? prev)
            => literal(`Out`, input, prev, "out");

    "Section 3.5.1 of the specification"
    rule
    shared InModifier inModifier(In t)
            => astNode(`InModifier`, [], t);

    "Section 3.5.1 of the specification"
    rule
    shared OutModifier outModifier(Out t)
            => astNode(`OutModifier`, [], t);

    "Section 3.5.3 of the specification"
    tokenizer
    shared Token<Given>? given_(String input, Object? prev)
            => literal(`Given`, input, prev, "given");

    "Section 3.5.3 of the specification"
    rule
    shared TypeConstraint typeConstraint(Given g, TypeName name,
            CaseTypes? cases, SatisfiedTypes? satisfieds)
            => astNode(`TypeConstraint`, [name, cases, satisfieds], g, name,
                    cases, satisfieds);

    "Section 3.6 of the specification"
    rule
    shared TypeArguments typeArguments(LT a, CommaSepList<TypeArgument> types,
            GT b)
            => astNode(`TypeArguments`, [types.nodes], a,
                    *types.tokens.chain({b}));

    "Section 3.6 of the specification"
    rule
    shared TypeArgument typeArgument(Variance? var, Type type)
            => astNode(`TypeArgument`, [type, var], var, type);
}
