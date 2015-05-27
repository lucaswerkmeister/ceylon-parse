import ceylon.language.meta.model {
    Generic,
    Type,
    Function
}

"A rule. Specifies produced and consumed symbols and a method to execute them"
shared class Rule {
    shared Object(Object?*) consume;
    shared ProductionClause[] consumes;
    shared Atom produces;
    shared Integer precedence;
    shared Associativity associativity;
    shared actual Integer hash;
    shared Grammar g;
    shared Object identifier;

    shared new (Function<Object,Nothing> consume,
            ProductionClause[] consumes,
            Atom produces,
            Integer precedence,
            Associativity associativity,
            Grammar g) {
        this.consume = (Object?* x) => consume.apply(*x);
        this.consumes = consumes;
        this.produces = produces;
        this.precedence = precedence;
        this.associativity = associativity;
        this.hash = consume.hash;
        this.g = g;
        this.identifier = consume.string;
    }

    shared new TupleRule(Type<Tuple<Anything,Anything,Anything[]>> tuple,
            Grammar g) {
        this.produces = Atom(tuple);
        this.consume = (Anything * a) => a;
        this.precedence = 0;
        this.associativity = nonassoc;

        assert(is Type<Anything[]>&Generic tuple);
        this.consumes = clausesFromTupleType(tuple, g);
        this.hash = tuple.hash;
        this.g = g;
        this.identifier = Atom(tuple);
    }

    shared actual Boolean equals(Object other) {
        if (! is Rule other) { return false; }
        assert(is Rule other);

        return other.identifier == identifier;
    }

    shared Boolean precedenceConflict(Rule other) {
        if (precedence >= other.precedence) { return false; }
        if (produces != other.produces) { return false; }
        if (bracketed || other.bracketed) { return false; }
        return true;
    }

    shared Boolean bracketed {
        if (exists c = consumes.first,
            produces.subtypeOf(c.atom)) { return false; }
        if (exists c = consumes.last,
            produces.subtypeOf(c.atom)) { return false; }
        return true;
    }

    shared Integer? forbidPosition(Rule other) {
        if (other.precedence != precedence) { return null; }
        if (other.associativity != associativity) { return null; }
        if (other.produces != produces) { return null; }

        if (associativity == rassoc) { return 0; }
        if (associativity == lassoc) { return consumes.size - 1; }
        return null;
    }

    shared void predictAll() { for (c in consumes) { c.predict(); } }
}
