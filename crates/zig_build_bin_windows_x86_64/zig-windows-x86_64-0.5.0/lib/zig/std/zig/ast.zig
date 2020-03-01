const std = @import("../std.zig");
const assert = std.debug.assert;
const testing = std.testing;
const SegmentedList = std.SegmentedList;
const mem = std.mem;
const Token = std.zig.Token;

pub const TokenIndex = usize;

pub const Tree = struct {
    source: []const u8,
    tokens: TokenList,
    root_node: *Node.Root,
    arena_allocator: std.heap.ArenaAllocator,
    errors: ErrorList,

    pub const TokenList = SegmentedList(Token, 64);
    pub const ErrorList = SegmentedList(Error, 0);

    pub fn deinit(self: *Tree) void {
        // Here we copy the arena allocator into stack memory, because
        // otherwise it would destroy itself while it was still working.
        var arena_allocator = self.arena_allocator;
        arena_allocator.deinit();
        // self is destroyed
    }

    pub fn renderError(self: *Tree, parse_error: *Error, stream: var) !void {
        return parse_error.render(&self.tokens, stream);
    }

    pub fn tokenSlice(self: *Tree, token_index: TokenIndex) []const u8 {
        return self.tokenSlicePtr(self.tokens.at(token_index));
    }

    pub fn tokenSlicePtr(self: *Tree, token: *const Token) []const u8 {
        return self.source[token.start..token.end];
    }

    pub fn getNodeSource(self: *const Tree, node: *const Node) []const u8 {
        const first_token = self.tokens.at(node.firstToken());
        const last_token = self.tokens.at(node.lastToken());
        return self.source[first_token.start..last_token.end];
    }

    pub const Location = struct {
        line: usize,
        column: usize,
        line_start: usize,
        line_end: usize,
    };

    /// Return the Location of the token relative to the offset specified by `start_index`.
    pub fn tokenLocationPtr(self: *Tree, start_index: usize, token: *const Token) Location {
        var loc = Location{
            .line = 0,
            .column = 0,
            .line_start = start_index,
            .line_end = self.source.len,
        };
        const token_start = token.start;
        for (self.source[start_index..]) |c, i| {
            if (i + start_index == token_start) {
                loc.line_end = i + start_index;
                while (loc.line_end < self.source.len and self.source[loc.line_end] != '\n') : (loc.line_end += 1) {}
                return loc;
            }
            if (c == '\n') {
                loc.line += 1;
                loc.column = 0;
                loc.line_start = i + 1;
            } else {
                loc.column += 1;
            }
        }
        return loc;
    }

    pub fn tokenLocation(self: *Tree, start_index: usize, token_index: TokenIndex) Location {
        return self.tokenLocationPtr(start_index, self.tokens.at(token_index));
    }

    pub fn tokensOnSameLine(self: *Tree, token1_index: TokenIndex, token2_index: TokenIndex) bool {
        return self.tokensOnSameLinePtr(self.tokens.at(token1_index), self.tokens.at(token2_index));
    }

    pub fn tokensOnSameLinePtr(self: *Tree, token1: *const Token, token2: *const Token) bool {
        return mem.indexOfScalar(u8, self.source[token1.end..token2.start], '\n') == null;
    }

    pub fn dump(self: *Tree) void {
        self.root_node.base.dump(0);
    }

    /// Skips over comments
    pub fn prevToken(self: *Tree, token_index: TokenIndex) TokenIndex {
        var index = token_index - 1;
        while (self.tokens.at(index).id == Token.Id.LineComment) {
            index -= 1;
        }
        return index;
    }

    /// Skips over comments
    pub fn nextToken(self: *Tree, token_index: TokenIndex) TokenIndex {
        var index = token_index + 1;
        while (self.tokens.at(index).id == Token.Id.LineComment) {
            index += 1;
        }
        return index;
    }
};

pub const Error = union(enum) {
    InvalidToken: InvalidToken,
    ExpectedContainerMembers: ExpectedContainerMembers,
    ExpectedStringLiteral: ExpectedStringLiteral,
    ExpectedIntegerLiteral: ExpectedIntegerLiteral,
    ExpectedPubItem: ExpectedPubItem,
    ExpectedIdentifier: ExpectedIdentifier,
    ExpectedStatement: ExpectedStatement,
    ExpectedVarDeclOrFn: ExpectedVarDeclOrFn,
    ExpectedVarDecl: ExpectedVarDecl,
    ExpectedReturnType: ExpectedReturnType,
    ExpectedAggregateKw: ExpectedAggregateKw,
    UnattachedDocComment: UnattachedDocComment,
    ExpectedEqOrSemi: ExpectedEqOrSemi,
    ExpectedSemiOrLBrace: ExpectedSemiOrLBrace,
    ExpectedSemiOrElse: ExpectedSemiOrElse,
    ExpectedLabelOrLBrace: ExpectedLabelOrLBrace,
    ExpectedLBrace: ExpectedLBrace,
    ExpectedColonOrRParen: ExpectedColonOrRParen,
    ExpectedLabelable: ExpectedLabelable,
    ExpectedInlinable: ExpectedInlinable,
    ExpectedAsmOutputReturnOrType: ExpectedAsmOutputReturnOrType,
    ExpectedCall: ExpectedCall,
    ExpectedCallOrFnProto: ExpectedCallOrFnProto,
    ExpectedSliceOrRBracket: ExpectedSliceOrRBracket,
    ExtraAlignQualifier: ExtraAlignQualifier,
    ExtraConstQualifier: ExtraConstQualifier,
    ExtraVolatileQualifier: ExtraVolatileQualifier,
    ExtraAllowZeroQualifier: ExtraAllowZeroQualifier,
    ExpectedTypeExpr: ExpectedTypeExpr,
    ExpectedPrimaryTypeExpr: ExpectedPrimaryTypeExpr,
    ExpectedParamType: ExpectedParamType,
    ExpectedExpr: ExpectedExpr,
    ExpectedPrimaryExpr: ExpectedPrimaryExpr,
    ExpectedToken: ExpectedToken,
    ExpectedCommaOrEnd: ExpectedCommaOrEnd,
    ExpectedParamList: ExpectedParamList,
    ExpectedPayload: ExpectedPayload,
    ExpectedBlockOrAssignment: ExpectedBlockOrAssignment,
    ExpectedBlockOrExpression: ExpectedBlockOrExpression,
    ExpectedExprOrAssignment: ExpectedExprOrAssignment,
    ExpectedPrefixExpr: ExpectedPrefixExpr,
    ExpectedLoopExpr: ExpectedLoopExpr,
    ExpectedDerefOrUnwrap: ExpectedDerefOrUnwrap,
    ExpectedSuffixOp: ExpectedSuffixOp,

    pub fn render(self: *const Error, tokens: *Tree.TokenList, stream: var) !void {
        switch (self.*) {
            .InvalidToken => |*x| return x.render(tokens, stream),
            .ExpectedContainerMembers => |*x| return x.render(tokens, stream),
            .ExpectedStringLiteral => |*x| return x.render(tokens, stream),
            .ExpectedIntegerLiteral => |*x| return x.render(tokens, stream),
            .ExpectedPubItem => |*x| return x.render(tokens, stream),
            .ExpectedIdentifier => |*x| return x.render(tokens, stream),
            .ExpectedStatement => |*x| return x.render(tokens, stream),
            .ExpectedVarDeclOrFn => |*x| return x.render(tokens, stream),
            .ExpectedVarDecl => |*x| return x.render(tokens, stream),
            .ExpectedReturnType => |*x| return x.render(tokens, stream),
            .ExpectedAggregateKw => |*x| return x.render(tokens, stream),
            .UnattachedDocComment => |*x| return x.render(tokens, stream),
            .ExpectedEqOrSemi => |*x| return x.render(tokens, stream),
            .ExpectedSemiOrLBrace => |*x| return x.render(tokens, stream),
            .ExpectedSemiOrElse => |*x| return x.render(tokens, stream),
            .ExpectedLabelOrLBrace => |*x| return x.render(tokens, stream),
            .ExpectedLBrace => |*x| return x.render(tokens, stream),
            .ExpectedColonOrRParen => |*x| return x.render(tokens, stream),
            .ExpectedLabelable => |*x| return x.render(tokens, stream),
            .ExpectedInlinable => |*x| return x.render(tokens, stream),
            .ExpectedAsmOutputReturnOrType => |*x| return x.render(tokens, stream),
            .ExpectedCall => |*x| return x.render(tokens, stream),
            .ExpectedCallOrFnProto => |*x| return x.render(tokens, stream),
            .ExpectedSliceOrRBracket => |*x| return x.render(tokens, stream),
            .ExtraAlignQualifier => |*x| return x.render(tokens, stream),
            .ExtraConstQualifier => |*x| return x.render(tokens, stream),
            .ExtraVolatileQualifier => |*x| return x.render(tokens, stream),
            .ExtraAllowZeroQualifier => |*x| return x.render(tokens, stream),
            .ExpectedTypeExpr => |*x| return x.render(tokens, stream),
            .ExpectedPrimaryTypeExpr => |*x| return x.render(tokens, stream),
            .ExpectedParamType => |*x| return x.render(tokens, stream),
            .ExpectedExpr => |*x| return x.render(tokens, stream),
            .ExpectedPrimaryExpr => |*x| return x.render(tokens, stream),
            .ExpectedToken => |*x| return x.render(tokens, stream),
            .ExpectedCommaOrEnd => |*x| return x.render(tokens, stream),
            .ExpectedParamList => |*x| return x.render(tokens, stream),
            .ExpectedPayload => |*x| return x.render(tokens, stream),
            .ExpectedBlockOrAssignment => |*x| return x.render(tokens, stream),
            .ExpectedBlockOrExpression => |*x| return x.render(tokens, stream),
            .ExpectedExprOrAssignment => |*x| return x.render(tokens, stream),
            .ExpectedPrefixExpr => |*x| return x.render(tokens, stream),
            .ExpectedLoopExpr => |*x| return x.render(tokens, stream),
            .ExpectedDerefOrUnwrap => |*x| return x.render(tokens, stream),
            .ExpectedSuffixOp => |*x| return x.render(tokens, stream),
        }
    }

    pub fn loc(self: *const Error) TokenIndex {
        switch (self.*) {
            .InvalidToken => |x| return x.token,
            .ExpectedContainerMembers => |x| return x.token,
            .ExpectedStringLiteral => |x| return x.token,
            .ExpectedIntegerLiteral => |x| return x.token,
            .ExpectedPubItem => |x| return x.token,
            .ExpectedIdentifier => |x| return x.token,
            .ExpectedStatement => |x| return x.token,
            .ExpectedVarDeclOrFn => |x| return x.token,
            .ExpectedVarDecl => |x| return x.token,
            .ExpectedReturnType => |x| return x.token,
            .ExpectedAggregateKw => |x| return x.token,
            .UnattachedDocComment => |x| return x.token,
            .ExpectedEqOrSemi => |x| return x.token,
            .ExpectedSemiOrLBrace => |x| return x.token,
            .ExpectedSemiOrElse => |x| return x.token,
            .ExpectedLabelOrLBrace => |x| return x.token,
            .ExpectedLBrace => |x| return x.token,
            .ExpectedColonOrRParen => |x| return x.token,
            .ExpectedLabelable => |x| return x.token,
            .ExpectedInlinable => |x| return x.token,
            .ExpectedAsmOutputReturnOrType => |x| return x.token,
            .ExpectedCall => |x| return x.node.firstToken(),
            .ExpectedCallOrFnProto => |x| return x.node.firstToken(),
            .ExpectedSliceOrRBracket => |x| return x.token,
            .ExtraAlignQualifier => |x| return x.token,
            .ExtraConstQualifier => |x| return x.token,
            .ExtraVolatileQualifier => |x| return x.token,
            .ExtraAllowZeroQualifier => |x| return x.token,
            .ExpectedTypeExpr => |x| return x.token,
            .ExpectedPrimaryTypeExpr => |x| return x.token,
            .ExpectedParamType => |x| return x.token,
            .ExpectedExpr => |x| return x.token,
            .ExpectedPrimaryExpr => |x| return x.token,
            .ExpectedToken => |x| return x.token,
            .ExpectedCommaOrEnd => |x| return x.token,
            .ExpectedParamList => |x| return x.token,
            .ExpectedPayload => |x| return x.token,
            .ExpectedBlockOrAssignment => |x| return x.token,
            .ExpectedBlockOrExpression => |x| return x.token,
            .ExpectedExprOrAssignment => |x| return x.token,
            .ExpectedPrefixExpr => |x| return x.token,
            .ExpectedLoopExpr => |x| return x.token,
            .ExpectedDerefOrUnwrap => |x| return x.token,
            .ExpectedSuffixOp => |x| return x.token,
        }
    }

    pub const InvalidToken = SingleTokenError("Invalid token '{}'");
    pub const ExpectedContainerMembers = SingleTokenError("Expected test, comptime, var decl, or container field, found '{}'");
    pub const ExpectedStringLiteral = SingleTokenError("Expected string literal, found '{}'");
    pub const ExpectedIntegerLiteral = SingleTokenError("Expected integer literal, found '{}'");
    pub const ExpectedIdentifier = SingleTokenError("Expected identifier, found '{}'");
    pub const ExpectedStatement = SingleTokenError("Expected statement, found '{}'");
    pub const ExpectedVarDeclOrFn = SingleTokenError("Expected variable declaration or function, found '{}'");
    pub const ExpectedVarDecl = SingleTokenError("Expected variable declaration, found '{}'");
    pub const ExpectedReturnType = SingleTokenError("Expected 'var' or return type expression, found '{}'");
    pub const ExpectedAggregateKw = SingleTokenError("Expected '" ++ Token.Id.Keyword_struct.symbol() ++ "', '" ++ Token.Id.Keyword_union.symbol() ++ "', or '" ++ Token.Id.Keyword_enum.symbol() ++ "', found '{}'");
    pub const ExpectedEqOrSemi = SingleTokenError("Expected '=' or ';', found '{}'");
    pub const ExpectedSemiOrLBrace = SingleTokenError("Expected ';' or '{{', found '{}'");
    pub const ExpectedSemiOrElse = SingleTokenError("Expected ';' or 'else', found '{}'");
    pub const ExpectedLBrace = SingleTokenError("Expected '{{', found '{}'");
    pub const ExpectedLabelOrLBrace = SingleTokenError("Expected label or '{{', found '{}'");
    pub const ExpectedColonOrRParen = SingleTokenError("Expected ':' or ')', found '{}'");
    pub const ExpectedLabelable = SingleTokenError("Expected 'while', 'for', 'inline', 'suspend', or '{{', found '{}'");
    pub const ExpectedInlinable = SingleTokenError("Expected 'while' or 'for', found '{}'");
    pub const ExpectedAsmOutputReturnOrType = SingleTokenError("Expected '->' or '" ++ Token.Id.Identifier.symbol() ++ "', found '{}'");
    pub const ExpectedSliceOrRBracket = SingleTokenError("Expected ']' or '..', found '{}'");
    pub const ExpectedTypeExpr = SingleTokenError("Expected type expression, found '{}'");
    pub const ExpectedPrimaryTypeExpr = SingleTokenError("Expected primary type expression, found '{}'");
    pub const ExpectedExpr = SingleTokenError("Expected expression, found '{}'");
    pub const ExpectedPrimaryExpr = SingleTokenError("Expected primary expression, found '{}'");
    pub const ExpectedParamList = SingleTokenError("Expected parameter list, found '{}'");
    pub const ExpectedPayload = SingleTokenError("Expected loop payload, found '{}'");
    pub const ExpectedBlockOrAssignment = SingleTokenError("Expected block or assignment, found '{}'");
    pub const ExpectedBlockOrExpression = SingleTokenError("Expected block or expression, found '{}'");
    pub const ExpectedExprOrAssignment = SingleTokenError("Expected expression or assignment, found '{}'");
    pub const ExpectedPrefixExpr = SingleTokenError("Expected prefix expression, found '{}'");
    pub const ExpectedLoopExpr = SingleTokenError("Expected loop expression, found '{}'");
    pub const ExpectedDerefOrUnwrap = SingleTokenError("Expected pointer dereference or optional unwrap, found '{}'");
    pub const ExpectedSuffixOp = SingleTokenError("Expected pointer dereference, optional unwrap, or field access, found '{}'");

    pub const ExpectedParamType = SimpleError("Expected parameter type");
    pub const ExpectedPubItem = SimpleError("Pub must be followed by fn decl, var decl, or container member");
    pub const UnattachedDocComment = SimpleError("Unattached documentation comment");
    pub const ExtraAlignQualifier = SimpleError("Extra align qualifier");
    pub const ExtraConstQualifier = SimpleError("Extra const qualifier");
    pub const ExtraVolatileQualifier = SimpleError("Extra volatile qualifier");
    pub const ExtraAllowZeroQualifier = SimpleError("Extra allowzero qualifier");

    pub const ExpectedCall = struct {
        node: *Node,

        pub fn render(self: *const ExpectedCall, tokens: *Tree.TokenList, stream: var) !void {
            return stream.print("expected " ++ @tagName(@TagType(Node.SuffixOp.Op).Call) ++ ", found {}", @tagName(self.node.id));
        }
    };

    pub const ExpectedCallOrFnProto = struct {
        node: *Node,

        pub fn render(self: *const ExpectedCallOrFnProto, tokens: *Tree.TokenList, stream: var) !void {
            return stream.print("expected " ++ @tagName(@TagType(Node.SuffixOp.Op).Call) ++ " or " ++ @tagName(Node.Id.FnProto) ++ ", found {}", @tagName(self.node.id));
        }
    };

    pub const ExpectedToken = struct {
        token: TokenIndex,
        expected_id: Token.Id,

        pub fn render(self: *const ExpectedToken, tokens: *Tree.TokenList, stream: var) !void {
            const found_token = tokens.at(self.token);
            switch (found_token.id) {
                .Invalid_ampersands => {
                    return stream.print("`&&` is invalid. Note that `and` is boolean AND.");
                },
                .Invalid => {
                    return stream.print("expected '{}', found invalid bytes", self.expected_id.symbol());
                },
                else => {
                    const token_name = found_token.id.symbol();
                    return stream.print("expected '{}', found '{}'", self.expected_id.symbol(), token_name);
                },
            }
        }
    };

    pub const ExpectedCommaOrEnd = struct {
        token: TokenIndex,
        end_id: Token.Id,

        pub fn render(self: *const ExpectedCommaOrEnd, tokens: *Tree.TokenList, stream: var) !void {
            const actual_token = tokens.at(self.token);
            return stream.print("expected ',' or '{}', found '{}'", self.end_id.symbol(), actual_token.id.symbol());
        }
    };

    fn SingleTokenError(comptime msg: []const u8) type {
        return struct {
            const ThisError = @This();

            token: TokenIndex,

            pub fn render(self: *const ThisError, tokens: *Tree.TokenList, stream: var) !void {
                const actual_token = tokens.at(self.token);
                return stream.print(msg, actual_token.id.symbol());
            }
        };
    }

    fn SimpleError(comptime msg: []const u8) type {
        return struct {
            const ThisError = @This();

            token: TokenIndex,

            pub fn render(self: *const ThisError, tokens: *Tree.TokenList, stream: var) !void {
                return stream.write(msg);
            }
        };
    }
};

pub const Node = struct {
    id: Id,

    pub const Id = enum {
        // Top level
        Root,
        Use,
        TestDecl,

        // Statements
        VarDecl,
        Defer,

        // Operators
        InfixOp,
        PrefixOp,
        SuffixOp,

        // Control flow
        Switch,
        While,
        For,
        If,
        ControlFlowExpression,
        Suspend,

        // Type expressions
        VarType,
        ErrorType,
        FnProto,
        AnyFrameType,

        // Primary expressions
        IntegerLiteral,
        FloatLiteral,
        EnumLiteral,
        StringLiteral,
        MultilineStringLiteral,
        CharLiteral,
        BoolLiteral,
        NullLiteral,
        UndefinedLiteral,
        Unreachable,
        Identifier,
        GroupedExpression,
        BuiltinCall,
        ErrorSetDecl,
        ContainerDecl,
        Asm,
        Comptime,
        Block,

        // Misc
        DocComment,
        SwitchCase,
        SwitchElse,
        Else,
        Payload,
        PointerPayload,
        PointerIndexPayload,
        ContainerField,
        ErrorTag,
        AsmInput,
        AsmOutput,
        ParamDecl,
        FieldInitializer,
    };

    pub fn cast(base: *Node, comptime T: type) ?*T {
        if (base.id == comptime typeToId(T)) {
            return @fieldParentPtr(T, "base", base);
        }
        return null;
    }

    pub fn iterate(base: *Node, index: usize) ?*Node {
        comptime var i = 0;
        inline while (i < @memberCount(Id)) : (i += 1) {
            if (base.id == @field(Id, @memberName(Id, i))) {
                const T = @field(Node, @memberName(Id, i));
                return @fieldParentPtr(T, "base", base).iterate(index);
            }
        }
        unreachable;
    }

    pub fn firstToken(base: *const Node) TokenIndex {
        comptime var i = 0;
        inline while (i < @memberCount(Id)) : (i += 1) {
            if (base.id == @field(Id, @memberName(Id, i))) {
                const T = @field(Node, @memberName(Id, i));
                return @fieldParentPtr(T, "base", base).firstToken();
            }
        }
        unreachable;
    }

    pub fn lastToken(base: *const Node) TokenIndex {
        comptime var i = 0;
        inline while (i < @memberCount(Id)) : (i += 1) {
            if (base.id == @field(Id, @memberName(Id, i))) {
                const T = @field(Node, @memberName(Id, i));
                return @fieldParentPtr(T, "base", base).lastToken();
            }
        }
        unreachable;
    }

    pub fn typeToId(comptime T: type) Id {
        comptime var i = 0;
        inline while (i < @memberCount(Id)) : (i += 1) {
            if (T == @field(Node, @memberName(Id, i))) {
                return @field(Id, @memberName(Id, i));
            }
        }
        unreachable;
    }

    pub fn requireSemiColon(base: *const Node) bool {
        var n = base;
        while (true) {
            switch (n.id) {
                Id.Root,
                Id.ContainerField,
                Id.ParamDecl,
                Id.Block,
                Id.Payload,
                Id.PointerPayload,
                Id.PointerIndexPayload,
                Id.Switch,
                Id.SwitchCase,
                Id.SwitchElse,
                Id.FieldInitializer,
                Id.DocComment,
                Id.TestDecl,
                => return false,
                Id.While => {
                    const while_node = @fieldParentPtr(While, "base", n);
                    if (while_node.@"else") |@"else"| {
                        n = &@"else".base;
                        continue;
                    }

                    return while_node.body.id != Id.Block;
                },
                Id.For => {
                    const for_node = @fieldParentPtr(For, "base", n);
                    if (for_node.@"else") |@"else"| {
                        n = &@"else".base;
                        continue;
                    }

                    return for_node.body.id != Id.Block;
                },
                Id.If => {
                    const if_node = @fieldParentPtr(If, "base", n);
                    if (if_node.@"else") |@"else"| {
                        n = &@"else".base;
                        continue;
                    }

                    return if_node.body.id != Id.Block;
                },
                Id.Else => {
                    const else_node = @fieldParentPtr(Else, "base", n);
                    n = else_node.body;
                    continue;
                },
                Id.Defer => {
                    const defer_node = @fieldParentPtr(Defer, "base", n);
                    return defer_node.expr.id != Id.Block;
                },
                Id.Comptime => {
                    const comptime_node = @fieldParentPtr(Comptime, "base", n);
                    return comptime_node.expr.id != Id.Block;
                },
                Id.Suspend => {
                    const suspend_node = @fieldParentPtr(Suspend, "base", n);
                    if (suspend_node.body) |body| {
                        return body.id != Id.Block;
                    }

                    return true;
                },
                else => return true,
            }
        }
    }

    pub fn dump(self: *Node, indent: usize) void {
        {
            var i: usize = 0;
            while (i < indent) : (i += 1) {
                std.debug.warn(" ");
            }
        }
        std.debug.warn("{}\n", @tagName(self.id));

        var child_i: usize = 0;
        while (self.iterate(child_i)) |child| : (child_i += 1) {
            child.dump(indent + 2);
        }
    }

    pub const Root = struct {
        base: Node,
        doc_comments: ?*DocComment,
        decls: DeclList,
        eof_token: TokenIndex,

        pub const DeclList = SegmentedList(*Node, 4);

        pub fn iterate(self: *Root, index: usize) ?*Node {
            if (index < self.decls.len) {
                return self.decls.at(index).*;
            }
            return null;
        }

        pub fn firstToken(self: *const Root) TokenIndex {
            return if (self.decls.len == 0) self.eof_token else (self.decls.at(0).*).firstToken();
        }

        pub fn lastToken(self: *const Root) TokenIndex {
            return if (self.decls.len == 0) self.eof_token else (self.decls.at(self.decls.len - 1).*).lastToken();
        }
    };

    pub const VarDecl = struct {
        base: Node,
        doc_comments: ?*DocComment,
        visib_token: ?TokenIndex,
        thread_local_token: ?TokenIndex,
        name_token: TokenIndex,
        eq_token: TokenIndex,
        mut_token: TokenIndex,
        comptime_token: ?TokenIndex,
        extern_export_token: ?TokenIndex,
        lib_name: ?*Node,
        type_node: ?*Node,
        align_node: ?*Node,
        section_node: ?*Node,
        init_node: ?*Node,
        semicolon_token: TokenIndex,

        pub fn iterate(self: *VarDecl, index: usize) ?*Node {
            var i = index;

            if (self.type_node) |type_node| {
                if (i < 1) return type_node;
                i -= 1;
            }

            if (self.align_node) |align_node| {
                if (i < 1) return align_node;
                i -= 1;
            }

            if (self.section_node) |section_node| {
                if (i < 1) return section_node;
                i -= 1;
            }

            if (self.init_node) |init_node| {
                if (i < 1) return init_node;
                i -= 1;
            }

            return null;
        }

        pub fn firstToken(self: *const VarDecl) TokenIndex {
            if (self.visib_token) |visib_token| return visib_token;
            if (self.thread_local_token) |thread_local_token| return thread_local_token;
            if (self.comptime_token) |comptime_token| return comptime_token;
            if (self.extern_export_token) |extern_export_token| return extern_export_token;
            assert(self.lib_name == null);
            return self.mut_token;
        }

        pub fn lastToken(self: *const VarDecl) TokenIndex {
            return self.semicolon_token;
        }
    };

    pub const Use = struct {
        base: Node,
        doc_comments: ?*DocComment,
        visib_token: ?TokenIndex,
        use_token: TokenIndex,
        expr: *Node,
        semicolon_token: TokenIndex,

        pub fn iterate(self: *Use, index: usize) ?*Node {
            var i = index;

            if (i < 1) return self.expr;
            i -= 1;

            return null;
        }

        pub fn firstToken(self: *const Use) TokenIndex {
            if (self.visib_token) |visib_token| return visib_token;
            return self.use_token;
        }

        pub fn lastToken(self: *const Use) TokenIndex {
            return self.semicolon_token;
        }
    };

    pub const ErrorSetDecl = struct {
        base: Node,
        error_token: TokenIndex,
        decls: DeclList,
        rbrace_token: TokenIndex,

        pub const DeclList = SegmentedList(*Node, 2);

        pub fn iterate(self: *ErrorSetDecl, index: usize) ?*Node {
            var i = index;

            if (i < self.decls.len) return self.decls.at(i).*;
            i -= self.decls.len;

            return null;
        }

        pub fn firstToken(self: *const ErrorSetDecl) TokenIndex {
            return self.error_token;
        }

        pub fn lastToken(self: *const ErrorSetDecl) TokenIndex {
            return self.rbrace_token;
        }
    };

    pub const ContainerDecl = struct {
        base: Node,
        layout_token: ?TokenIndex,
        kind_token: TokenIndex,
        init_arg_expr: InitArg,
        fields_and_decls: DeclList,
        lbrace_token: TokenIndex,
        rbrace_token: TokenIndex,

        pub const DeclList = Root.DeclList;

        pub const InitArg = union(enum) {
            None,
            Enum: ?*Node,
            Type: *Node,
        };

        pub fn iterate(self: *ContainerDecl, index: usize) ?*Node {
            var i = index;

            switch (self.init_arg_expr) {
                InitArg.Type => |t| {
                    if (i < 1) return t;
                    i -= 1;
                },
                InitArg.None, InitArg.Enum => {},
            }

            if (i < self.fields_and_decls.len) return self.fields_and_decls.at(i).*;
            i -= self.fields_and_decls.len;

            return null;
        }

        pub fn firstToken(self: *const ContainerDecl) TokenIndex {
            if (self.layout_token) |layout_token| {
                return layout_token;
            }
            return self.kind_token;
        }

        pub fn lastToken(self: *const ContainerDecl) TokenIndex {
            return self.rbrace_token;
        }
    };

    pub const ContainerField = struct {
        base: Node,
        doc_comments: ?*DocComment,
        visib_token: ?TokenIndex,
        name_token: TokenIndex,
        type_expr: ?*Node,
        value_expr: ?*Node,
        align_expr: ?*Node,

        pub fn iterate(self: *ContainerField, index: usize) ?*Node {
            var i = index;

            if (self.type_expr) |type_expr| {
                if (i < 1) return type_expr;
                i -= 1;
            }

            if (self.value_expr) |value_expr| {
                if (i < 1) return value_expr;
                i -= 1;
            }

            return null;
        }

        pub fn firstToken(self: *const ContainerField) TokenIndex {
            if (self.visib_token) |visib_token| return visib_token;
            return self.name_token;
        }

        pub fn lastToken(self: *const ContainerField) TokenIndex {
            if (self.value_expr) |value_expr| {
                return value_expr.lastToken();
            }
            if (self.type_expr) |type_expr| {
                return type_expr.lastToken();
            }

            return self.name_token;
        }
    };

    pub const ErrorTag = struct {
        base: Node,
        doc_comments: ?*DocComment,
        name_token: TokenIndex,

        pub fn iterate(self: *ErrorTag, index: usize) ?*Node {
            var i = index;

            if (self.doc_comments) |comments| {
                if (i < 1) return &comments.base;
                i -= 1;
            }

            return null;
        }

        pub fn firstToken(self: *const ErrorTag) TokenIndex {
            return self.name_token;
        }

        pub fn lastToken(self: *const ErrorTag) TokenIndex {
            return self.name_token;
        }
    };

    pub const Identifier = struct {
        base: Node,
        token: TokenIndex,

        pub fn iterate(self: *Identifier, index: usize) ?*Node {
            return null;
        }

        pub fn firstToken(self: *const Identifier) TokenIndex {
            return self.token;
        }

        pub fn lastToken(self: *const Identifier) TokenIndex {
            return self.token;
        }
    };

    pub const FnProto = struct {
        base: Node,
        doc_comments: ?*DocComment,
        visib_token: ?TokenIndex,
        fn_token: TokenIndex,
        name_token: ?TokenIndex,
        params: ParamList,
        return_type: ReturnType,
        var_args_token: ?TokenIndex,
        extern_export_inline_token: ?TokenIndex,
        cc_token: ?TokenIndex,
        body_node: ?*Node,
        lib_name: ?*Node, // populated if this is an extern declaration
        align_expr: ?*Node, // populated if align(A) is present
        section_expr: ?*Node, // populated if linksection(A) is present

        pub const ParamList = SegmentedList(*Node, 2);

        pub const ReturnType = union(enum) {
            Explicit: *Node,
            InferErrorSet: *Node,
        };

        pub fn iterate(self: *FnProto, index: usize) ?*Node {
            var i = index;

            if (self.lib_name) |lib_name| {
                if (i < 1) return lib_name;
                i -= 1;
            }

            if (i < self.params.len) return self.params.at(self.params.len - i - 1).*;
            i -= self.params.len;

            if (self.align_expr) |align_expr| {
                if (i < 1) return align_expr;
                i -= 1;
            }

            if (self.section_expr) |section_expr| {
                if (i < 1) return section_expr;
                i -= 1;
            }

            switch (self.return_type) {
                // TODO allow this and next prong to share bodies since the types are the same
                ReturnType.Explicit => |node| {
                    if (i < 1) return node;
                    i -= 1;
                },
                ReturnType.InferErrorSet => |node| {
                    if (i < 1) return node;
                    i -= 1;
                },
            }

            if (self.body_node) |body_node| {
                if (i < 1) return body_node;
                i -= 1;
            }

            return null;
        }

        pub fn firstToken(self: *const FnProto) TokenIndex {
            if (self.visib_token) |visib_token| return visib_token;
            if (self.extern_export_inline_token) |extern_export_inline_token| return extern_export_inline_token;
            assert(self.lib_name == null);
            if (self.cc_token) |cc_token| return cc_token;
            return self.fn_token;
        }

        pub fn lastToken(self: *const FnProto) TokenIndex {
            if (self.body_node) |body_node| return body_node.lastToken();
            switch (self.return_type) {
                // TODO allow this and next prong to share bodies since the types are the same
                ReturnType.Explicit => |node| return node.lastToken(),
                ReturnType.InferErrorSet => |node| return node.lastToken(),
            }
        }
    };

    pub const AnyFrameType = struct {
        base: Node,
        anyframe_token: TokenIndex,
        result: ?Result,

        pub const Result = struct {
            arrow_token: TokenIndex,
            return_type: *Node,
        };

        pub fn iterate(self: *AnyFrameType, index: usize) ?*Node {
            var i = index;

            if (self.result) |result| {
                if (i < 1) return result.return_type;
                i -= 1;
            }

            return null;
        }

        pub fn firstToken(self: *const AnyFrameType) TokenIndex {
            return self.anyframe_token;
        }

        pub fn lastToken(self: *const AnyFrameType) TokenIndex {
            if (self.result) |result| return result.return_type.lastToken();
            return self.anyframe_token;
        }
    };

    pub const ParamDecl = struct {
        base: Node,
        doc_comments: ?*DocComment,
        comptime_token: ?TokenIndex,
        noalias_token: ?TokenIndex,
        name_token: ?TokenIndex,
        type_node: *Node,
        var_args_token: ?TokenIndex,

        pub fn iterate(self: *ParamDecl, index: usize) ?*Node {
            var i = index;

            if (i < 1) return self.type_node;
            i -= 1;

            return null;
        }

        pub fn firstToken(self: *const ParamDecl) TokenIndex {
            if (self.comptime_token) |comptime_token| return comptime_token;
            if (self.noalias_token) |noalias_token| return noalias_token;
            if (self.name_token) |name_token| return name_token;
            return self.type_node.firstToken();
        }

        pub fn lastToken(self: *const ParamDecl) TokenIndex {
            if (self.var_args_token) |var_args_token| return var_args_token;
            return self.type_node.lastToken();
        }
    };

    pub const Block = struct {
        base: Node,
        label: ?TokenIndex,
        lbrace: TokenIndex,
        statements: StatementList,
        rbrace: TokenIndex,

        pub const StatementList = Root.DeclList;

        pub fn iterate(self: *Block, index: usize) ?*Node {
            var i = index;

            if (i < self.statements.len) return self.statements.at(i).*;
            i -= self.statements.len;

            return null;
        }

        pub fn firstToken(self: *const Block) TokenIndex {
            if (self.label) |label| {
                return label;
            }

            return self.lbrace;
        }

        pub fn lastToken(self: *const Block) TokenIndex {
            return self.rbrace;
        }
    };

    pub const Defer = struct {
        base: Node,
        defer_token: TokenIndex,
        expr: *Node,

        pub fn iterate(self: *Defer, index: usize) ?*Node {
            var i = index;

            if (i < 1) return self.expr;
            i -= 1;

            return null;
        }

        pub fn firstToken(self: *const Defer) TokenIndex {
            return self.defer_token;
        }

        pub fn lastToken(self: *const Defer) TokenIndex {
            return self.expr.lastToken();
        }
    };

    pub const Comptime = struct {
        base: Node,
        doc_comments: ?*DocComment,
        comptime_token: TokenIndex,
        expr: *Node,

        pub fn iterate(self: *Comptime, index: usize) ?*Node {
            var i = index;

            if (i < 1) return self.expr;
            i -= 1;

            return null;
        }

        pub fn firstToken(self: *const Comptime) TokenIndex {
            return self.comptime_token;
        }

        pub fn lastToken(self: *const Comptime) TokenIndex {
            return self.expr.lastToken();
        }
    };

    pub const Payload = struct {
        base: Node,
        lpipe: TokenIndex,
        error_symbol: *Node,
        rpipe: TokenIndex,

        pub fn iterate(self: *Payload, index: usize) ?*Node {
            var i = index;

            if (i < 1) return self.error_symbol;
            i -= 1;

            return null;
        }

        pub fn firstToken(self: *const Payload) TokenIndex {
            return self.lpipe;
        }

        pub fn lastToken(self: *const Payload) TokenIndex {
            return self.rpipe;
        }
    };

    pub const PointerPayload = struct {
        base: Node,
        lpipe: TokenIndex,
        ptr_token: ?TokenIndex,
        value_symbol: *Node,
        rpipe: TokenIndex,

        pub fn iterate(self: *PointerPayload, index: usize) ?*Node {
            var i = index;

            if (i < 1) return self.value_symbol;
            i -= 1;

            return null;
        }

        pub fn firstToken(self: *const PointerPayload) TokenIndex {
            return self.lpipe;
        }

        pub fn lastToken(self: *const PointerPayload) TokenIndex {
            return self.rpipe;
        }
    };

    pub const PointerIndexPayload = struct {
        base: Node,
        lpipe: TokenIndex,
        ptr_token: ?TokenIndex,
        value_symbol: *Node,
        index_symbol: ?*Node,
        rpipe: TokenIndex,

        pub fn iterate(self: *PointerIndexPayload, index: usize) ?*Node {
            var i = index;

            if (i < 1) return self.value_symbol;
            i -= 1;

            if (self.index_symbol) |index_symbol| {
                if (i < 1) return index_symbol;
                i -= 1;
            }

            return null;
        }

        pub fn firstToken(self: *const PointerIndexPayload) TokenIndex {
            return self.lpipe;
        }

        pub fn lastToken(self: *const PointerIndexPayload) TokenIndex {
            return self.rpipe;
        }
    };

    pub const Else = struct {
        base: Node,
        else_token: TokenIndex,
        payload: ?*Node,
        body: *Node,

        pub fn iterate(self: *Else, index: usize) ?*Node {
            var i = index;

            if (self.payload) |payload| {
                if (i < 1) return payload;
                i -= 1;
            }

            if (i < 1) return self.body;
            i -= 1;

            return null;
        }

        pub fn firstToken(self: *const Else) TokenIndex {
            return self.else_token;
        }

        pub fn lastToken(self: *const Else) TokenIndex {
            return self.body.lastToken();
        }
    };

    pub const Switch = struct {
        base: Node,
        switch_token: TokenIndex,
        expr: *Node,

        /// these must be SwitchCase nodes
        cases: CaseList,
        rbrace: TokenIndex,

        pub const CaseList = SegmentedList(*Node, 2);

        pub fn iterate(self: *Switch, index: usize) ?*Node {
            var i = index;

            if (i < 1) return self.expr;
            i -= 1;

            if (i < self.cases.len) return self.cases.at(i).*;
            i -= self.cases.len;

            return null;
        }

        pub fn firstToken(self: *const Switch) TokenIndex {
            return self.switch_token;
        }

        pub fn lastToken(self: *const Switch) TokenIndex {
            return self.rbrace;
        }
    };

    pub const SwitchCase = struct {
        base: Node,
        items: ItemList,
        arrow_token: TokenIndex,
        payload: ?*Node,
        expr: *Node,

        pub const ItemList = SegmentedList(*Node, 1);

        pub fn iterate(self: *SwitchCase, index: usize) ?*Node {
            var i = index;

            if (i < self.items.len) return self.items.at(i).*;
            i -= self.items.len;

            if (self.payload) |payload| {
                if (i < 1) return payload;
                i -= 1;
            }

            if (i < 1) return self.expr;
            i -= 1;

            return null;
        }

        pub fn firstToken(self: *const SwitchCase) TokenIndex {
            return (self.items.at(0).*).firstToken();
        }

        pub fn lastToken(self: *const SwitchCase) TokenIndex {
            return self.expr.lastToken();
        }
    };

    pub const SwitchElse = struct {
        base: Node,
        token: TokenIndex,

        pub fn iterate(self: *SwitchElse, index: usize) ?*Node {
            return null;
        }

        pub fn firstToken(self: *const SwitchElse) TokenIndex {
            return self.token;
        }

        pub fn lastToken(self: *const SwitchElse) TokenIndex {
            return self.token;
        }
    };

    pub const While = struct {
        base: Node,
        label: ?TokenIndex,
        inline_token: ?TokenIndex,
        while_token: TokenIndex,
        condition: *Node,
        payload: ?*Node,
        continue_expr: ?*Node,
        body: *Node,
        @"else": ?*Else,

        pub fn iterate(self: *While, index: usize) ?*Node {
            var i = index;

            if (i < 1) return self.condition;
            i -= 1;

            if (self.payload) |payload| {
                if (i < 1) return payload;
                i -= 1;
            }

            if (self.continue_expr) |continue_expr| {
                if (i < 1) return continue_expr;
                i -= 1;
            }

            if (i < 1) return self.body;
            i -= 1;

            if (self.@"else") |@"else"| {
                if (i < 1) return &@"else".base;
                i -= 1;
            }

            return null;
        }

        pub fn firstToken(self: *const While) TokenIndex {
            if (self.label) |label| {
                return label;
            }

            if (self.inline_token) |inline_token| {
                return inline_token;
            }

            return self.while_token;
        }

        pub fn lastToken(self: *const While) TokenIndex {
            if (self.@"else") |@"else"| {
                return @"else".body.lastToken();
            }

            return self.body.lastToken();
        }
    };

    pub const For = struct {
        base: Node,
        label: ?TokenIndex,
        inline_token: ?TokenIndex,
        for_token: TokenIndex,
        array_expr: *Node,
        payload: *Node,
        body: *Node,
        @"else": ?*Else,

        pub fn iterate(self: *For, index: usize) ?*Node {
            var i = index;

            if (i < 1) return self.array_expr;
            i -= 1;

            if (i < 1) return self.payload;
            i -= 1;

            if (i < 1) return self.body;
            i -= 1;

            if (self.@"else") |@"else"| {
                if (i < 1) return &@"else".base;
                i -= 1;
            }

            return null;
        }

        pub fn firstToken(self: *const For) TokenIndex {
            if (self.label) |label| {
                return label;
            }

            if (self.inline_token) |inline_token| {
                return inline_token;
            }

            return self.for_token;
        }

        pub fn lastToken(self: *const For) TokenIndex {
            if (self.@"else") |@"else"| {
                return @"else".body.lastToken();
            }

            return self.body.lastToken();
        }
    };

    pub const If = struct {
        base: Node,
        if_token: TokenIndex,
        condition: *Node,
        payload: ?*Node,
        body: *Node,
        @"else": ?*Else,

        pub fn iterate(self: *If, index: usize) ?*Node {
            var i = index;

            if (i < 1) return self.condition;
            i -= 1;

            if (self.payload) |payload| {
                if (i < 1) return payload;
                i -= 1;
            }

            if (i < 1) return self.body;
            i -= 1;

            if (self.@"else") |@"else"| {
                if (i < 1) return &@"else".base;
                i -= 1;
            }

            return null;
        }

        pub fn firstToken(self: *const If) TokenIndex {
            return self.if_token;
        }

        pub fn lastToken(self: *const If) TokenIndex {
            if (self.@"else") |@"else"| {
                return @"else".body.lastToken();
            }

            return self.body.lastToken();
        }
    };

    pub const InfixOp = struct {
        base: Node,
        op_token: TokenIndex,
        lhs: *Node,
        op: Op,
        rhs: *Node,

        pub const Op = union(enum) {
            Add,
            AddWrap,
            ArrayCat,
            ArrayMult,
            Assign,
            AssignBitAnd,
            AssignBitOr,
            AssignBitShiftLeft,
            AssignBitShiftRight,
            AssignBitXor,
            AssignDiv,
            AssignMinus,
            AssignMinusWrap,
            AssignMod,
            AssignPlus,
            AssignPlusWrap,
            AssignTimes,
            AssignTimesWarp,
            BangEqual,
            BitAnd,
            BitOr,
            BitShiftLeft,
            BitShiftRight,
            BitXor,
            BoolAnd,
            BoolOr,
            Catch: ?*Node,
            Div,
            EqualEqual,
            ErrorUnion,
            GreaterOrEqual,
            GreaterThan,
            LessOrEqual,
            LessThan,
            MergeErrorSets,
            Mod,
            Mult,
            MultWrap,
            Period,
            Range,
            Sub,
            SubWrap,
            UnwrapOptional,
        };

        pub fn iterate(self: *InfixOp, index: usize) ?*Node {
            var i = index;

            if (i < 1) return self.lhs;
            i -= 1;

            switch (self.op) {
                Op.Catch => |maybe_payload| {
                    if (maybe_payload) |payload| {
                        if (i < 1) return payload;
                        i -= 1;
                    }
                },

                Op.Add,
                Op.AddWrap,
                Op.ArrayCat,
                Op.ArrayMult,
                Op.Assign,
                Op.AssignBitAnd,
                Op.AssignBitOr,
                Op.AssignBitShiftLeft,
                Op.AssignBitShiftRight,
                Op.AssignBitXor,
                Op.AssignDiv,
                Op.AssignMinus,
                Op.AssignMinusWrap,
                Op.AssignMod,
                Op.AssignPlus,
                Op.AssignPlusWrap,
                Op.AssignTimes,
                Op.AssignTimesWarp,
                Op.BangEqual,
                Op.BitAnd,
                Op.BitOr,
                Op.BitShiftLeft,
                Op.BitShiftRight,
                Op.BitXor,
                Op.BoolAnd,
                Op.BoolOr,
                Op.Div,
                Op.EqualEqual,
                Op.ErrorUnion,
                Op.GreaterOrEqual,
                Op.GreaterThan,
                Op.LessOrEqual,
                Op.LessThan,
                Op.MergeErrorSets,
                Op.Mod,
                Op.Mult,
                Op.MultWrap,
                Op.Period,
                Op.Range,
                Op.Sub,
                Op.SubWrap,
                Op.UnwrapOptional,
                => {},
            }

            if (i < 1) return self.rhs;
            i -= 1;

            return null;
        }

        pub fn firstToken(self: *const InfixOp) TokenIndex {
            return self.lhs.firstToken();
        }

        pub fn lastToken(self: *const InfixOp) TokenIndex {
            return self.rhs.lastToken();
        }
    };

    pub const PrefixOp = struct {
        base: Node,
        op_token: TokenIndex,
        op: Op,
        rhs: *Node,

        pub const Op = union(enum) {
            AddressOf,
            ArrayType: *Node,
            Await,
            BitNot,
            BoolNot,
            Cancel,
            OptionalType,
            Negation,
            NegationWrap,
            Resume,
            PtrType: PtrInfo,
            SliceType: PtrInfo,
            Try,
        };

        pub const PtrInfo = struct {
            allowzero_token: ?TokenIndex,
            align_info: ?Align,
            const_token: ?TokenIndex,
            volatile_token: ?TokenIndex,

            pub const Align = struct {
                node: *Node,
                bit_range: ?BitRange,

                pub const BitRange = struct {
                    start: *Node,
                    end: *Node,
                };
            };
        };

        pub fn iterate(self: *PrefixOp, index: usize) ?*Node {
            var i = index;

            switch (self.op) {
                // TODO https://github.com/ziglang/zig/issues/1107
                Op.SliceType => |addr_of_info| {
                    if (addr_of_info.align_info) |align_info| {
                        if (i < 1) return align_info.node;
                        i -= 1;
                    }
                },

                Op.PtrType => |addr_of_info| {
                    if (addr_of_info.align_info) |align_info| {
                        if (i < 1) return align_info.node;
                        i -= 1;
                    }
                },

                Op.ArrayType => |size_expr| {
                    if (i < 1) return size_expr;
                    i -= 1;
                },

                Op.AddressOf,
                Op.Await,
                Op.BitNot,
                Op.BoolNot,
                Op.Cancel,
                Op.OptionalType,
                Op.Negation,
                Op.NegationWrap,
                Op.Try,
                Op.Resume,
                => {},
            }

            if (i < 1) return self.rhs;
            i -= 1;

            return null;
        }

        pub fn firstToken(self: *const PrefixOp) TokenIndex {
            return self.op_token;
        }

        pub fn lastToken(self: *const PrefixOp) TokenIndex {
            return self.rhs.lastToken();
        }
    };

    pub const FieldInitializer = struct {
        base: Node,
        period_token: TokenIndex,
        name_token: TokenIndex,
        expr: *Node,

        pub fn iterate(self: *FieldInitializer, index: usize) ?*Node {
            var i = index;

            if (i < 1) return self.expr;
            i -= 1;

            return null;
        }

        pub fn firstToken(self: *const FieldInitializer) TokenIndex {
            return self.period_token;
        }

        pub fn lastToken(self: *const FieldInitializer) TokenIndex {
            return self.expr.lastToken();
        }
    };

    pub const SuffixOp = struct {
        base: Node,
        lhs: *Node,
        op: Op,
        rtoken: TokenIndex,

        pub const Op = union(enum) {
            Call: Call,
            ArrayAccess: *Node,
            Slice: Slice,
            ArrayInitializer: InitList,
            StructInitializer: InitList,
            Deref,
            UnwrapOptional,

            pub const InitList = SegmentedList(*Node, 2);

            pub const Call = struct {
                params: ParamList,
                async_token: ?TokenIndex,

                pub const ParamList = SegmentedList(*Node, 2);
            };

            pub const Slice = struct {
                start: *Node,
                end: ?*Node,
            };
        };

        pub fn iterate(self: *SuffixOp, index: usize) ?*Node {
            var i = index;

            if (i < 1) return self.lhs;
            i -= 1;

            switch (self.op) {
                .Call => |*call_info| {
                    if (i < call_info.params.len) return call_info.params.at(i).*;
                    i -= call_info.params.len;
                },
                .ArrayAccess => |index_expr| {
                    if (i < 1) return index_expr;
                    i -= 1;
                },
                .Slice => |range| {
                    if (i < 1) return range.start;
                    i -= 1;

                    if (range.end) |end| {
                        if (i < 1) return end;
                        i -= 1;
                    }
                },
                .ArrayInitializer => |*exprs| {
                    if (i < exprs.len) return exprs.at(i).*;
                    i -= exprs.len;
                },
                .StructInitializer => |*fields| {
                    if (i < fields.len) return fields.at(i).*;
                    i -= fields.len;
                },
                .UnwrapOptional,
                .Deref,
                => {},
            }

            return null;
        }

        pub fn firstToken(self: *const SuffixOp) TokenIndex {
            switch (self.op) {
                .Call => |*call_info| if (call_info.async_token) |async_token| return async_token,
                else => {},
            }
            return self.lhs.firstToken();
        }

        pub fn lastToken(self: *const SuffixOp) TokenIndex {
            return self.rtoken;
        }
    };

    pub const GroupedExpression = struct {
        base: Node,
        lparen: TokenIndex,
        expr: *Node,
        rparen: TokenIndex,

        pub fn iterate(self: *GroupedExpression, index: usize) ?*Node {
            var i = index;

            if (i < 1) return self.expr;
            i -= 1;

            return null;
        }

        pub fn firstToken(self: *const GroupedExpression) TokenIndex {
            return self.lparen;
        }

        pub fn lastToken(self: *const GroupedExpression) TokenIndex {
            return self.rparen;
        }
    };

    pub const ControlFlowExpression = struct {
        base: Node,
        ltoken: TokenIndex,
        kind: Kind,
        rhs: ?*Node,

        pub const Kind = union(enum) {
            Break: ?*Node,
            Continue: ?*Node,
            Return,
        };

        pub fn iterate(self: *ControlFlowExpression, index: usize) ?*Node {
            var i = index;

            switch (self.kind) {
                Kind.Break => |maybe_label| {
                    if (maybe_label) |label| {
                        if (i < 1) return label;
                        i -= 1;
                    }
                },
                Kind.Continue => |maybe_label| {
                    if (maybe_label) |label| {
                        if (i < 1) return label;
                        i -= 1;
                    }
                },
                Kind.Return => {},
            }

            if (self.rhs) |rhs| {
                if (i < 1) return rhs;
                i -= 1;
            }

            return null;
        }

        pub fn firstToken(self: *const ControlFlowExpression) TokenIndex {
            return self.ltoken;
        }

        pub fn lastToken(self: *const ControlFlowExpression) TokenIndex {
            if (self.rhs) |rhs| {
                return rhs.lastToken();
            }

            switch (self.kind) {
                Kind.Break => |maybe_label| {
                    if (maybe_label) |label| {
                        return label.lastToken();
                    }
                },
                Kind.Continue => |maybe_label| {
                    if (maybe_label) |label| {
                        return label.lastToken();
                    }
                },
                Kind.Return => return self.ltoken,
            }

            return self.ltoken;
        }
    };

    pub const Suspend = struct {
        base: Node,
        suspend_token: TokenIndex,
        body: ?*Node,

        pub fn iterate(self: *Suspend, index: usize) ?*Node {
            var i = index;

            if (self.body) |body| {
                if (i < 1) return body;
                i -= 1;
            }

            return null;
        }

        pub fn firstToken(self: *const Suspend) TokenIndex {
            return self.suspend_token;
        }

        pub fn lastToken(self: *const Suspend) TokenIndex {
            if (self.body) |body| {
                return body.lastToken();
            }

            return self.suspend_token;
        }
    };

    pub const IntegerLiteral = struct {
        base: Node,
        token: TokenIndex,

        pub fn iterate(self: *IntegerLiteral, index: usize) ?*Node {
            return null;
        }

        pub fn firstToken(self: *const IntegerLiteral) TokenIndex {
            return self.token;
        }

        pub fn lastToken(self: *const IntegerLiteral) TokenIndex {
            return self.token;
        }
    };

    pub const EnumLiteral = struct {
        base: Node,
        dot: TokenIndex,
        name: TokenIndex,

        pub fn iterate(self: *EnumLiteral, index: usize) ?*Node {
            return null;
        }

        pub fn firstToken(self: *const EnumLiteral) TokenIndex {
            return self.dot;
        }

        pub fn lastToken(self: *const EnumLiteral) TokenIndex {
            return self.name;
        }
    };

    pub const FloatLiteral = struct {
        base: Node,
        token: TokenIndex,

        pub fn iterate(self: *FloatLiteral, index: usize) ?*Node {
            return null;
        }

        pub fn firstToken(self: *const FloatLiteral) TokenIndex {
            return self.token;
        }

        pub fn lastToken(self: *const FloatLiteral) TokenIndex {
            return self.token;
        }
    };

    pub const BuiltinCall = struct {
        base: Node,
        builtin_token: TokenIndex,
        params: ParamList,
        rparen_token: TokenIndex,

        pub const ParamList = SegmentedList(*Node, 2);

        pub fn iterate(self: *BuiltinCall, index: usize) ?*Node {
            var i = index;

            if (i < self.params.len) return self.params.at(i).*;
            i -= self.params.len;

            return null;
        }

        pub fn firstToken(self: *const BuiltinCall) TokenIndex {
            return self.builtin_token;
        }

        pub fn lastToken(self: *const BuiltinCall) TokenIndex {
            return self.rparen_token;
        }
    };

    pub const StringLiteral = struct {
        base: Node,
        token: TokenIndex,

        pub fn iterate(self: *StringLiteral, index: usize) ?*Node {
            return null;
        }

        pub fn firstToken(self: *const StringLiteral) TokenIndex {
            return self.token;
        }

        pub fn lastToken(self: *const StringLiteral) TokenIndex {
            return self.token;
        }
    };

    pub const MultilineStringLiteral = struct {
        base: Node,
        lines: LineList,

        pub const LineList = SegmentedList(TokenIndex, 4);

        pub fn iterate(self: *MultilineStringLiteral, index: usize) ?*Node {
            return null;
        }

        pub fn firstToken(self: *const MultilineStringLiteral) TokenIndex {
            return self.lines.at(0).*;
        }

        pub fn lastToken(self: *const MultilineStringLiteral) TokenIndex {
            return self.lines.at(self.lines.len - 1).*;
        }
    };

    pub const CharLiteral = struct {
        base: Node,
        token: TokenIndex,

        pub fn iterate(self: *CharLiteral, index: usize) ?*Node {
            return null;
        }

        pub fn firstToken(self: *const CharLiteral) TokenIndex {
            return self.token;
        }

        pub fn lastToken(self: *const CharLiteral) TokenIndex {
            return self.token;
        }
    };

    pub const BoolLiteral = struct {
        base: Node,
        token: TokenIndex,

        pub fn iterate(self: *BoolLiteral, index: usize) ?*Node {
            return null;
        }

        pub fn firstToken(self: *const BoolLiteral) TokenIndex {
            return self.token;
        }

        pub fn lastToken(self: *const BoolLiteral) TokenIndex {
            return self.token;
        }
    };

    pub const NullLiteral = struct {
        base: Node,
        token: TokenIndex,

        pub fn iterate(self: *NullLiteral, index: usize) ?*Node {
            return null;
        }

        pub fn firstToken(self: *const NullLiteral) TokenIndex {
            return self.token;
        }

        pub fn lastToken(self: *const NullLiteral) TokenIndex {
            return self.token;
        }
    };

    pub const UndefinedLiteral = struct {
        base: Node,
        token: TokenIndex,

        pub fn iterate(self: *UndefinedLiteral, index: usize) ?*Node {
            return null;
        }

        pub fn firstToken(self: *const UndefinedLiteral) TokenIndex {
            return self.token;
        }

        pub fn lastToken(self: *const UndefinedLiteral) TokenIndex {
            return self.token;
        }
    };

    pub const AsmOutput = struct {
        base: Node,
        lbracket: TokenIndex,
        symbolic_name: *Node,
        constraint: *Node,
        kind: Kind,
        rparen: TokenIndex,

        pub const Kind = union(enum) {
            Variable: *Identifier,
            Return: *Node,
        };

        pub fn iterate(self: *AsmOutput, index: usize) ?*Node {
            var i = index;

            if (i < 1) return self.symbolic_name;
            i -= 1;

            if (i < 1) return self.constraint;
            i -= 1;

            switch (self.kind) {
                Kind.Variable => |variable_name| {
                    if (i < 1) return &variable_name.base;
                    i -= 1;
                },
                Kind.Return => |return_type| {
                    if (i < 1) return return_type;
                    i -= 1;
                },
            }

            return null;
        }

        pub fn firstToken(self: *const AsmOutput) TokenIndex {
            return self.lbracket;
        }

        pub fn lastToken(self: *const AsmOutput) TokenIndex {
            return self.rparen;
        }
    };

    pub const AsmInput = struct {
        base: Node,
        lbracket: TokenIndex,
        symbolic_name: *Node,
        constraint: *Node,
        expr: *Node,
        rparen: TokenIndex,

        pub fn iterate(self: *AsmInput, index: usize) ?*Node {
            var i = index;

            if (i < 1) return self.symbolic_name;
            i -= 1;

            if (i < 1) return self.constraint;
            i -= 1;

            if (i < 1) return self.expr;
            i -= 1;

            return null;
        }

        pub fn firstToken(self: *const AsmInput) TokenIndex {
            return self.lbracket;
        }

        pub fn lastToken(self: *const AsmInput) TokenIndex {
            return self.rparen;
        }
    };

    pub const Asm = struct {
        base: Node,
        asm_token: TokenIndex,
        volatile_token: ?TokenIndex,
        template: *Node,
        outputs: OutputList,
        inputs: InputList,
        clobbers: ClobberList,
        rparen: TokenIndex,

        pub const OutputList = SegmentedList(*AsmOutput, 2);
        pub const InputList = SegmentedList(*AsmInput, 2);
        pub const ClobberList = SegmentedList(*Node, 2);

        pub fn iterate(self: *Asm, index: usize) ?*Node {
            var i = index;

            if (i < self.outputs.len) return &self.outputs.at(index).*.base;
            i -= self.outputs.len;

            if (i < self.inputs.len) return &self.inputs.at(index).*.base;
            i -= self.inputs.len;

            return null;
        }

        pub fn firstToken(self: *const Asm) TokenIndex {
            return self.asm_token;
        }

        pub fn lastToken(self: *const Asm) TokenIndex {
            return self.rparen;
        }
    };

    pub const Unreachable = struct {
        base: Node,
        token: TokenIndex,

        pub fn iterate(self: *Unreachable, index: usize) ?*Node {
            return null;
        }

        pub fn firstToken(self: *const Unreachable) TokenIndex {
            return self.token;
        }

        pub fn lastToken(self: *const Unreachable) TokenIndex {
            return self.token;
        }
    };

    pub const ErrorType = struct {
        base: Node,
        token: TokenIndex,

        pub fn iterate(self: *ErrorType, index: usize) ?*Node {
            return null;
        }

        pub fn firstToken(self: *const ErrorType) TokenIndex {
            return self.token;
        }

        pub fn lastToken(self: *const ErrorType) TokenIndex {
            return self.token;
        }
    };

    pub const VarType = struct {
        base: Node,
        token: TokenIndex,

        pub fn iterate(self: *VarType, index: usize) ?*Node {
            return null;
        }

        pub fn firstToken(self: *const VarType) TokenIndex {
            return self.token;
        }

        pub fn lastToken(self: *const VarType) TokenIndex {
            return self.token;
        }
    };

    pub const DocComment = struct {
        base: Node,
        lines: LineList,

        pub const LineList = SegmentedList(TokenIndex, 4);

        pub fn iterate(self: *DocComment, index: usize) ?*Node {
            return null;
        }

        pub fn firstToken(self: *const DocComment) TokenIndex {
            return self.lines.at(0).*;
        }

        pub fn lastToken(self: *const DocComment) TokenIndex {
            return self.lines.at(self.lines.len - 1).*;
        }
    };

    pub const TestDecl = struct {
        base: Node,
        doc_comments: ?*DocComment,
        test_token: TokenIndex,
        name: *Node,
        body_node: *Node,

        pub fn iterate(self: *TestDecl, index: usize) ?*Node {
            var i = index;

            if (i < 1) return self.body_node;
            i -= 1;

            return null;
        }

        pub fn firstToken(self: *const TestDecl) TokenIndex {
            return self.test_token;
        }

        pub fn lastToken(self: *const TestDecl) TokenIndex {
            return self.body_node.lastToken();
        }
    };
};

test "iterate" {
    var root = Node.Root{
        .base = Node{ .id = Node.Id.Root },
        .doc_comments = null,
        .decls = Node.Root.DeclList.init(std.debug.global_allocator),
        .eof_token = 0,
    };
    var base = &root.base;
    testing.expect(base.iterate(0) == null);
}
