require "minitest/autorun"
require "assert_scanner"

$v = true # enables "redundant message" phase

class TestAssertScanner < Minitest::Test
  make_my_diffs_pretty!

  def self.todo msg
    define_method "test_#{msg}" do
      skip "not yet"
    end
  end

  def c(msg, *args); s(:call, nil, msg, *args);  end
  def a(*args);      c(:assert, *args);          end
  def r(*args);      c(:refute, *args);          end
  def e(l,m,*r);     s(:call, c(:_, l), m, *r);  end
  def aeq(*args);    c(:assert_equal, *args);    end
  def ain(*args);    c(:assert_includes, *args); end
  def blk(*a);       s(:iter, c(:_), 0, *a);     end
  def bm(*a, m, r);  s(:call, blk(*a), m, r);    end
  def meq(l,r);      e(l, :must_equal,    r);    end
  def lit(x);        s(:lit, x);                 end

  def test_sanity
    ruby = %(assert [1, 2, 3].include?(b) == true, "is b in 1..3?")
    sexp = RubyParser.new.process ruby
    scan = AssertScanner.new

    scan.analyze_assert sexp

    lhs = s(:array, s(:lit, 1), s(:lit, 2), s(:lit, 3))
    rhs = c(:b)
    inc = s(:call, lhs, :include?, rhs)

    exp = {
      c(:assert, s(:call, inc, :==, s(:true)))          => "redundant message?",
      c(:assert_equal, inc, s(:true))                   => "assert_equal exp, act",
      c(:assert_equal, s(:true), inc)                   => "assert_equal exp, act",
      c(:assert_operator, lhs, s(:lit, :include?), rhs) => "assert_operator obj, msg, arg",
      c(:assert_includes, lhs, rhs)                     => "assert_includes enum, val",
    }

    assert_equal exp, scan.io

    exp = [
      #  assert([1, 2, 3].include?(b) == true, "is b in 1..3?") # original
      "  assert(([1, 2, 3].include?(b) == true))   # redundant message?",
      "  assert_equal([1, 2, 3].include?(b), true) # assert_equal exp, act",
      "  assert_equal(true, [1, 2, 3].include?(b)) # assert_equal exp, act",
      "  assert_operator([1, 2, 3], :include?, b)  # assert_operator obj, msg, arg",
      "  assert_includes([1, 2, 3], b)             # assert_includes enum, val",
    ]

    assert_equal exp, scan.out
  end

  def assert_pattern scanner, from, msg = nil, to = nil
    pattern = AssertScanner.const_get scanner
    scan = AssertScanner.new
    proc = AssertScanner.assertions[pattern]

    scan.instance_exec from, &proc

    assert_operator pattern, :===, from
    assert_match pattern, from

    if msg && to
      exp = {to => msg}

      assert_equal exp, scan.io
    else
      assert_empty scan.io
    end
  end

  def assert_re scanner, msg, from, to
    assert_pattern scanner, from, msg, to
  end

  def assert_re_done scanner, from
    assert_pattern scanner, from
  end

  def test_re_msg
    assert_re(:RE_MSG,
              "redundant message?",
              a(:lhs, s(:str, "message")),
              a(:lhs))
  end

  def test_re_not
    assert_re(:RE_NOT,
              "refute not_cond",
              a(s(:call, :lhs, :!)),
              # =>
              r(:lhs))
  end

  def test_re_equal
    assert_re(:RE_EQUAL,
              "assert_equal exp, act",
              a(s(:call, :lhs, :==, :rhs)),
              # =>
              aeq(:lhs, :rhs))
  end

  def test_re_nequal
    assert_re(:RE_NEQUAL,
              "refute_equal exp, act",
              a(s(:call, :lhs, :!=, :rhs)),
              # =>
              c(:refute_equal, :lhs, :rhs))
  end

  def test_re_incl
    assert_re(:RE_INCL,
              "assert_includes obj, val",
              a(s(:call, :lhs, :include?, :rhs)),
              # =>
              ain(:lhs, :rhs))
  end

  def test_re_pred
    assert_re(:RE_PRED,
              "assert_predicate obj, msg",
              a(s(:call, :lhs, :pred?)),
              # =>
              c(:assert_predicate, :lhs, lit(:pred?)))
  end

  def test_re_oper
    assert_re(:RE_OPER,
              "assert_operator obj, msg, arg",
              a(s(:call, :lhs, :msg, :rhs)),
              # =>
              c(:assert_operator, :lhs, lit(:msg), :rhs))
  end

  def test_re_eq_msg
    assert_re(:RE_EQ_MSG,
              "redundant message?",
              aeq(:lhs, :rhs, :msg),
              # =>
              aeq(:lhs, :rhs))
  end

  def test_re_eq_nil
    assert_re(:RE_EQ_NIL,
              "assert_nil obj",
              aeq(s(:nil), :whatever),
              # =>
              c(:assert_nil, :whatever))
  end

  def test_re_eq_pred
    assert_re(:RE_EQ_PRED,
              "assert_predicate obj, msg",
              aeq(s(:true), s(:call, :obj, :msg)),
              # =>
              c(:assert_predicate, :obj, lit(:msg)))
  end

  def test_re_eq_oper
    assert_re(:RE_EQ_OPER,
              "assert_operator obj, msg, arg",
              aeq(s(:true), s(:call, :obj, :msg, :rhs)),
              # =>
              c(:assert_operator, :obj, lit(:msg), :rhs))
  end

  def test_re_eq_lhs_str
    long = "string " * 100
    short = long[0, 20]

    assert_re(:RE_EQ_LHS_STR,
              "assert_includes actual, substr",
              aeq(s(:str, long), :rhs),
              # =>
              ain(:rhs, s(:str, short)))
  end

  def test_re_eq_rhs_lit
    assert_re(:RE_EQ_RHS_LIT,
              "assert_equal exp, act",
              aeq(:act, lit(:val)),
              # =>
              aeq(lit(:val), :act))
  end

  def test_re_eq_rhs_str
    assert_re(:RE_EQ_RHS_STR,
              "assert_equal exp, act",
              aeq(:act, s(:str, "str")),
              # =>
              aeq(s(:str, "str"), :act))
  end

  def test_re_eq_rhs_ntf__nil
    assert_re(:RE_EQ_RHS_NTF,
              "assert_equal exp, act",
              aeq(:act, s(:nil)),
              # =>
              aeq(s(:nil), :act))
  end

  def test_re_eq_rhs_ntf__true
    assert_re(:RE_EQ_RHS_NTF,
              "assert_equal exp, act",
              aeq(:act, s(:true)),
              # =>
              aeq(s(:true), :act))
  end

  def test_re_eq_rhs_ntf__false
    assert_re(:RE_EQ_RHS_NTF,
              "assert_equal exp, act",
              aeq(:act, s(:false)),
              # =>
              aeq(s(:false), :act))
  end

  def test_re_eq_empty
    assert_re(:RE_EQ_EMPTY,
              "assert_empty",
              aeq(lit(0), s(:call, :whatever, :length)),
              # =>
              c(:assert_empty, :whatever))
  end

  def test_re_ref_msg
    assert_re(:RE_REF_MSG,
              "redundant message?",
              r(:test, s(:str, "msg")),
              # =>
              r(:test))
  end

  def test_re_ref_not
    assert_re(:RE_REF_NOT,
              "assert cond",
              r(s(:call, :lhs, :!)),
              # =>
              a(:lhs))
  end

  def test_re_ref_incl
    assert_re(:RE_REF_INCL,
              "refute_includes obj, val",
              r(s(:call, :lhs, :include?, :rhs)),
              # =>
              c(:refute_includes, :lhs, :rhs))
  end

  def test_re_ref_pred
    assert_re(:RE_REF_PRED,
              "refute_predicate obj, msg",
              r(s(:call, :lhs, :msg)),
              # =>
              c(:refute_predicate, :lhs, lit(:msg)))
  end

  def test_re_ref_oper
    assert_re(:RE_REF_OPER,
              "refute_operator obj, msg, arg",
              r(s(:call, :lhs, :msg, :rhs)),
              # =>
              c(:refute_operator, :lhs, lit(:msg), :rhs))
  end

  def test_re_op_incl
    assert_re(:RE_OP_INCL,
              "assert_includes enum, val",
              c(:assert_operator, :lhs, lit(:include?), :rhs),
              # =>
              ain(:lhs, :rhs))
  end

  def test_must_plain
    assert_re(:RE_MUST_PLAIN,
              "_(act).must_equal exp",
              s(:call, :lhs, :must_equal, :rhs),
              # =>
              meq(:lhs, :rhs))
  end

  def test_must_plain_good
    assert_re_done(:RE_MUST_GOOD,
                   e(:lhs, :must_xxx, :rhs))
  end

  def test_must_block_good
    assert_re_done(:RE_MUST_BLOCK_GOOD,
                   bm(:lhs, :must_xxx, :rhs))
  end

  def test_must_plain_expect
    assert_re(:RE_MUST_OTHER,
              "_(act).must_equal exp",
              s(:call, c(:expect, :act), :must_equal, :exp),
              # =>
              meq(:act, :exp))
  end

  def test_must_plain_value
    assert_re(:RE_MUST_OTHER,
              "_(act).must_equal exp",
              s(:call, c(:value, :act), :must_equal, :exp),
              # =>
              meq(:act, :exp))
  end

  def test_must_equal_rhs_ntf__nil
    assert_re(:RE_MUST_EQ_NIL,
              "_(act).must_be_nil",
              meq(:lhs, s(:nil)),
              # =>
              e(:lhs, :must_be_nil))
  end

  def test_must_include
    assert_re(:RE_MUST_INCLUDE,
              "_(obj).must_include val",
              meq(s(:call, :lhs, :include?, :rhs), s(:true)),
              # =>
              e(:lhs, :must_include, :rhs))
  end

  def test_must_be__pred
    assert_re(:RE_MUST_BE_PRED,
              "_(obj).must_be msg",
              meq(s(:call, :lhs, :msg?), s(:true)),
              # =>
              e(:lhs, :must_be, lit(:msg?)))
  end

  def test_must_be__op
    assert_re(:RE_MUST_BE_OPER,
              "_(obj).must_be msg, arg",
              meq(s(:call, :lhs, :msg, :rhs), s(:true)),
              # =>
              e(:lhs, :must_be, lit(:msg), :rhs))
  end

  def test_wont_include
    assert_re(:RE_WONT_INCLUDE,
              "_(obj).wont_include val",
              meq(s(:call, :lhs, :include?, :rhs), s(:false)),
              # =>
              e(:lhs, :wont_include, :rhs))
  end

  def test_wont_be__pred
    assert_re(:RE_WONT_BE_PRED,
              "_(obj).wont_be msg",
              meq(s(:call, :lhs, :msg?), s(:false)),
              # =>
              e(:lhs, :wont_be, lit(:msg?)))
  end

  def test_wont_be__op
    assert_re(:RE_WONT_BE_OPER,
              "_(obj).wont_be msg, arg",
              meq(s(:call, :lhs, :msg, :rhs), s(:false)),
              # =>
              e(:lhs, :wont_be, lit(:msg), :rhs))
  end

  def test_re_plain
    assert_re(:RE_PLAIN,
              "Try to not use plain assert",
              a(:whatever),
              # =>
              a(:whatever))
  end

  todo :assert
  todo :assert_empty
  # todo :assert_equal
  # todo :assert_equal_nil
  # todo :assert_equal_pred
  # todo :assert_equal_oper
  # todo :assert_equal_lhs_str
  # todo :assert_equal_rhs_lit
  # todo :assert_equal_rhs_str
  # todo :assert_equal_rhs_ntf__nil
  # todo :assert_equal_rhs_ntf__true
  # todo :assert_equal_rhs_ntf__false
  # todo :assert_equal_empty
  todo :assert_in_delta
  todo :assert_in_epsilon
  todo :assert_includes
  todo :assert_instance_of
  todo :assert_kind_of
  todo :assert_match
  todo :assert_nil
  todo :assert_operator
  todo :assert_output
  todo :assert_predicate
  todo :assert_raises
  todo :assert_respond_to
  todo :assert_same
  todo :assert_send
  todo :assert_silent
  todo :assert_throws
  todo :refute
  todo :refute_empty
  todo :refute_equal
  todo :refute_in_delta
  todo :refute_in_epsilon
  todo :refute_includes
  todo :refute_instance_of
  todo :refute_kind_of
  todo :refute_match
  todo :refute_nil
  todo :refute_operator
  todo :refute_predicate
  todo :refute_respond_to
  todo :refute_same

  todo :must_equal
  todo :must_equal_true
  todo :must_equal_false
  todo :must_equal_pred
  todo :must_equal_oper

  todo :must_equal_big_string
  todo :must_equal_assert_equal?
  todo :must_equal_lhs_str
  todo :must_equal_rhs_lit
  todo :must_equal_rhs_str
  todo :must_equal_rhs_ntf__true
  todo :must_equal_rhs_ntf__false
  todo :must_equal_empty

  todo :must_be_empty
  todo :must_be_close_to
  todo :must_be_within_epsilon
  todo :must_be_instance_of
  todo :must_be_kind_of
  todo :must_match
  todo :must_output
  todo :must_raise
  todo :must_respond_to
  todo :must_be_same_as
  todo :must_be_silent
  todo :must_throw

  todo :wont_be_empty
  todo :wont_equal
  todo :wont_be_close_to
  todo :wont_be_within_epsilon
  todo :wont_be_instance_of
  todo :wont_be_kind_of
  todo :wont_match
  todo :wont_be_nil
  todo :wont_respond_to
  todo :wont_be_same_as
end
