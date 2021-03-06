class CalendarEvent < ActiveRecord::Base
  belongs_to :calendar
  belongs_to :event_type, :class_name => 'CalendarEventType', 
      :foreign_key => :calendar_event_type_id

  has_many :mods, :class_name => 'CalendarEventMod', :dependent => :destroy
  has_many :recurrences, :class_name=>'CalendarRecurrence', :dependent => :destroy
  has_many :event_dates, :class_name=>'CalendarEventDate', :readonly => true
  has_many :dates, :through => :event_dates, :readonly => true

  (0..6).each do |n|
     attr_accessor "_repeat_#{n}".to_sym
     
     define_method "repeat_#{n}=" do |*args|
       sym = "@_repeat_#{n}".to_sym
       selected = args.first == '1'|| args.first == true
       self.instance_variable_set(sym, selected)
     end
     
     define_method "repeat_#{n}" do
       var = self.instance_variable_get("@_repeat_#{n}".to_sym)
       return var unless var.nil?
       return recurrences.find_by_weekday(n) ? true : false
     end
   end
  
  validates_presence_of :calendar, :start_date, :calendar_event_type_id
  before_save :create_dates_for_range
  # after_save :add_occurrences
  after_save :add_recurrences

  scope :with_time_set, :conditions => 'calendar_event_dates.start_time IS NOT NULL AND calendar_event_dates.end_time IS NOT NULL'
  scope :without_time_set, :conditions => 'calendar_event_dates.start_time IS NULL OR calendar_event_dates.end_time IS NULL'
  
  # def to_rrules
  #   return nil unless recurrences
  #   rrules = []
  #   weekly = []
  #   recurrences.each do |recurrence|
  #     if recurrence.monthly?
  #       rrules << (params = {'FREQ' => 'MONTHLY'})
  #       if !recurrence.weekly?
  #         params['BYMONTHDAY'] = recurrence.monthday.to_s
  #       else
  #         icalmw = ((mw = recurrence.monthweek) >= 0) ? mw + 1 : mw
  #         icaldc = Icalendar::DAYCODES[recurrence.weekday]
  #         params['BYDAY'] = icalmw.to_s + icaldc
  #       end
  #     else
  #       weekly << recurrence.weekday
  #     end
  #   end
  #   if !weekly.empty?
  #     rrules << {'FREQ' => 'WEEKLY',
  #       'BYDAY' => weekly.map {|w| Icalendar::DAYCODES[w]}.join(',')}
  #   end
  #   rrules
  # end
  
  def date_range
    e_date = self.end_date.blank? ? self.start_date : self.end_date
    self.start_date.to_date..e_date.to_date
  end

  def event_type_matches?(*event_types)
    return false unless event_type
    name = event_type.name.to_sym
    event_types.each {|et| return true if et.to_sym == name }
    return false
  end

  def any_weekday_selected?
    (0..6).each do |n|
      return true if weekday_selected?(n)
    end
    return false
  end

  def weekday_selected?(n)
    self.send("repeat_#{n}") == true
  end

  # creates Calendar Event Mods for new dates by date value
  # takes an array 
  def add_dates_by_date_value(date_values)
    transaction do
      date_values.each do |date_value|
        next if date_value.blank? 
        begin
          CalendarDate.create_for_date(date_value.to_date)
          event_date = event_dates.first(:conditions => {:date_value => date_value})
          next if event_date && !event_date.removed?
          if event_date
            event_date.mod.destroy
          else
            date_id = CalendarDate.find_by_value(date_value).id
            mods.create(:calendar_date_id => date_id)
          end
        rescue
          errors.add_to_base("Invalid date: #{date_value}")
          raise ActiveRecord::Rollback
        end
      end
    end
  end

  # creates Calendar Event Mods for removed dates by date id
  # takes an array
  def remove_dates_by_id(date_ids)
    date_ids.each do |id|
      next if id.blank?
      event_date = event_dates.first(:conditions => {:calendar_date_id => id})
      next unless event_date && !event_date.removed?
      if event_date.added? || event_date.modified?
        event_date.mod.destroy
      end
      unless event_date.added?
        mods.create(:calendar_date_id => id, :removed => true)
      end
    end
  end

  protected
  def create_dates_for_range
    CalendarDate.get_and_create_dates(self.date_range)
  end
  
  # def add_occurrences
  #   if event_type.name == "norepeat"
  #     self.recurrences = []
  #     self.occurrences = []
  #     date_range.each {|d| self.occurrences << CalendarDate.by_values(d) }
  #   end
  # end
  
  def add_recurrences
    if event_type_matches?(:norepeat, :weekdays, :daily)
      self.recurrences = []
    else
      (0..6).each {|n| self.send("repeat_#{n}=", self.send("repeat_#{n}"))}
      self.recurrences = []
      # self.occurrences = []
      self.recurrences.create(parse_recurrence_params_by_type)
    end
  end
  
  def parse_recurrence_params_by_type
    if event_type_matches?(:weekly)
      arr = []
      (0..6).each {|n| arr << {:weekday => n} if weekday_selected?(n) }
      arr
    elsif event_type_matches?(:monthly, :yearly)
      {:monthday => start_date.mday, :weekday => start_date.wday, 
       :monthweek => (start_date.mday - 1) / 7, :month => start_date.month}
    end
  end
end
