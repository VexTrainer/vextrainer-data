namespace VexTrainer.Data.Models;

/// <summary>
/// Represents everything the client needs to render a single topic page, bundled into
/// one object so the API can serve the entire screen in a single round trip.
///
/// The data is grouped into four logical sections:
///
///   1. Current topic  — the content identifier and read status for the topic being viewed.
///   2. Navigation     — prev/next topic references so the client can render forward/back
///                       buttons without fetching the full topic list for the parent lesson.
///   3. Breadcrumb     — the Module → Lesson → (optional parent H3 topic) → Topic trail
///                       so the user always knows where they are in the curriculum hierarchy.
///   4. Heading level  — controls how the topic is styled and whether it is a top-level
///                       section (H3) or a sub-topic nested under an H3 (H4).
///
/// Content for the topic itself is not stored here; it lives in a file on the server
/// whose path is derived from FileName. This model carries only the metadata and
/// navigation context needed to locate and frame that file.
///
/// Populated by sp_GetTopicDetails and returned via LessonService.GetTopicDetailsAsync.
/// </summary>
public class TopicDetails {
  // -------------------------------------------------------------------------
  // Current topic
  // -------------------------------------------------------------------------

  /// <summary>
  /// Primary key of this topic in the database.
  /// </summary>
  public int TopicId { get; set; }

  /// <summary>
  /// Display title shown in the heading and breadcrumb for this topic.
  /// </summary>
  public string TopicTitle { get; set; } = "";

  /// <summary>
  /// Controls the HTML heading level used to render this topic's title.
  /// 3 = H3 (top-level section within a lesson).
  /// 4 = H4 (sub-topic nested under an H3 section).
  /// The client uses this to apply the correct visual hierarchy and indentation.
  /// </summary>
  public byte HeadingLevel { get; set; }

  /// <summary>
  /// The file identifier used to locate the topic's content file on the server.
  /// Follows a zero-padded segment format that encodes the Module, Lesson, and Topic
  /// positions, e.g., "00100-00025-00010". The client or API constructs the full
  /// file path from this value.
  /// </summary>
  public string FileName { get; set; } = "";

  /// <summary>
  /// True if the current user has already read this topic; false otherwise.
  /// Drives read-state indicators (e.g., checkmarks) in the UI without requiring
  /// a separate progress query.
  /// </summary>
  public bool IsRead { get; set; }

  // -------------------------------------------------------------------------
  // Previous topic (navigation)
  // -------------------------------------------------------------------------

  /// <summary>
  /// Database ID of the topic that precedes this one in display_order, or null if
  /// this is the first topic in the lesson. Used by the client to enable or disable
  /// the "back" navigation button.
  /// </summary>
  public int? PreviousTopicId { get; set; }

  /// <summary>
  /// Display title of the previous topic, shown in the navigation control so the
  /// user knows where "back" will take them before tapping.
  /// </summary>
  public string? PreviousTopicTitle { get; set; }

  /// <summary>
  /// File identifier of the previous topic's content file, e.g., "00100-00025-00000".
  /// Allows the client to prefetch or directly navigate to the previous topic's content
  /// using the same file-resolution logic as the current topic.
  /// </summary>
  public string? PreviousFileName { get; set; }

  // -------------------------------------------------------------------------
  // Next topic (navigation)
  // -------------------------------------------------------------------------

  /// <summary>
  /// Database ID of the topic that follows this one in display_order, or null if
  /// this is the last topic in the lesson. Used by the client to enable or disable
  /// the "next" navigation button.
  /// </summary>
  public int? NextTopicId { get; set; }

  /// <summary>
  /// Display title of the next topic, shown in the navigation control so the user
  /// knows where "next" will take them before tapping.
  /// </summary>
  public string? NextTopicTitle { get; set; }

  /// <summary>
  /// File identifier of the next topic's content file, e.g., "00100-00025-00020".
  /// Allows the client to prefetch or directly navigate to the next topic's content
  /// using the same file-resolution logic as the current topic.
  /// </summary>
  public string? NextFileName { get; set; }

  // -------------------------------------------------------------------------
  // Breadcrumb
  // -------------------------------------------------------------------------

  /// <summary>
  /// Primary key of the module this topic belongs to. Used alongside ModuleName to
  /// build the first segment of the breadcrumb and to construct deep-link navigation.
  /// </summary>
  public short ModuleId { get; set; }

  /// <summary>
  /// Display name of the parent module, shown as the root of the breadcrumb trail,
  /// e.g., "Autonomous Programming".
  /// </summary>
  public string ModuleName { get; set; } = "";

  /// <summary>
  /// Primary key of the lesson this topic belongs to. Used alongside LessonTitle to
  /// build the second segment of the breadcrumb.
  /// </summary>
  public short LessonId { get; set; }

  /// <summary>
  /// Display title of the parent lesson, shown as the second segment of the breadcrumb
  /// trail, e.g., "PID Controllers".
  /// </summary>
  public string LessonTitle { get; set; } = "";

  /// <summary>
  /// For H4 sub-topics only: the title of the parent H3 topic that contains this one.
  /// Inserted between LessonTitle and TopicTitle in the breadcrumb so the full path
  /// reads Module → Lesson → H3 Topic → H4 Sub-topic.
  /// Null for H3 topics, which sit directly under the lesson with no intermediate parent.
  /// </summary>
  public string? ParentTopicTitle { get; set; }
}