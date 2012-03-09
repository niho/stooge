require File.expand_path('../../lib/stooge', __FILE__)
require 'test/unit'

#Stooge.logger {}

class StoogeTest < Test::Unit::TestCase
  def setup
    #Stooge.clear!
    $result = -1
    $handled = false
  end

  def with_an_error_handler
    Stooge.error do |e, job_name, args|
      $handled = e.class
      $job_name = job_name
      $job_args = args
    end
  end

  def test_enqueue_and_work_a_job
    EM.synchrony do
      val = rand(999999)
      deferrable = EM::DefaultDeferrable.new
      Stooge.job('test.job') do |args| 
        if val == args['val']
          $result = val
          deferrable.set_deferred_status :succeeded
        end
      end
      Stooge.enqueue('test.job', :val => val)
      Stooge.check_all
      EM::Synchrony.sync deferrable
      assert_equal val, $result
      AMQP.stop
      EM.stop
    end
  end

  # def test_invoke_error_handler_when_defined
  #   with_an_error_handler
  #   Stooge.job('my.job') { |args| fail }
  #   Stooge.enqueue('my.job', :foo => 123)
  #   Stooge.prep
  #   Stooge.work_one_job
  #   assert $handled
  #   assert_equal 'my.job', $job_name
  #   assert_equal({'foo' => 123}, $job_args)
  # end
  # 
  # def test_should_be_compatible_with_legacy_error_handlers
  #   exception = StandardError.new("Oh my, the job has failed!")
  #   Stooge.error { |e| $handled = e }
  #   Stooge.job('my.job') { |args| raise exception }
  #   Stooge.enqueue('my.job', :foo => 123)
  #   Stooge.prep
  #   Stooge.work_one_job
  #   assert_equal exception, $handled
  # end
  # 
  # def test_continue_working_when_error_handler_not_defined
  #   Stooge.job('my.job') { fail }
  #   Stooge.enqueue('my.job')
  #   Stooge.prep
  #   Stooge.work_one_job
  #   assert_equal false, $handled
  # end
  # 
  # def test_exception_raised_one_second_before_beanstalk_ttr_reached
  #   with_an_error_handler
  #   Stooge.job('my.job') { sleep(3); $handled = "didn't time out" }
  #   Stooge.enqueue('my.job', {}, :ttr => 2)
  #   Stooge.prep
  #   Stooge.work_one_job
  #   assert_equal Stooge::JobTimeout, $handled
  # end
  # 
  # def test_before_filter_gets_run_first
  #   Stooge.before { |name| $flag = "i_was_here" }
  #   Stooge.job('my.job') { |args| $handled = ($flag == 'i_was_here') }
  #   Stooge.enqueue('my.job')
  #   Stooge.prep
  #   Stooge.work_one_job
  #   assert_equal true, $handled
  # end
  # 
  # def test_before_filter_passes_the_name_of_the_job
  #   Stooge.before { |name| $jobname = name }
  #   Stooge.job('my.job') { true }
  #   Stooge.enqueue('my.job')
  #   Stooge.prep
  #   Stooge.work_one_job
  #   assert_equal 'my.job', $jobname
  # end
  # 
  # def test_before_filter_can_pass_an_instance_var
  #   Stooge.before { |name| @foo = "hello" }
  #   Stooge.job('my.job') { |args| $handled = (@foo == "hello") }
  #   Stooge.enqueue('my.job')
  #   Stooge.prep
  #   Stooge.work_one_job
  #   assert_equal true, $handled
  # end
  # 
  # def test_before_filter_invokes_error_handler_when_defined
  #   with_an_error_handler
  #   Stooge.before { |name| fail }
  #   Stooge.job('my.job') {  }
  #   Stooge.enqueue('my.job', :foo => 123)
  #   Stooge.prep
  #   Stooge.work_one_job
  #   assert $handled
  #   assert_equal 'my.job', $job_name
  #   assert_equal({'foo' => 123}, $job_args)
  # end

end
